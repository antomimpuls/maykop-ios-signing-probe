param(
    [Parameter(Mandatory = $true)]
    [string]$IPAPath
)

# Inspect profiles in a returned, re-signed probe. Exit 0 only qualifies it for
# device testing. It does not establish Apple trust, revocation or device match.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Security.Cryptography.Pkcs

function Find-PlistValue {
    param([System.Xml.Linq.XElement]$Dictionary, [string]$Key)
    $children = @($Dictionary.Elements())
    for ($index = 0; $index -lt ($children.Count - 1); $index += 2) {
        if ($children[$index].Name.LocalName -eq 'key' -and $children[$index].Value -eq $Key) {
            return ,$children[$index + 1]
        }
    }
    return $null
}

function Read-ProfileSummary {
    param([System.IO.Compression.ZipArchiveEntry]$Entry, [string]$Role)
    if ($Entry.Length -gt 4MB) { throw 'Profile exceeds inspection size limit.' }
    $profileStream = $Entry.Open()
    $profileMemory = [System.IO.MemoryStream]::new()
    try { $profileStream.CopyTo($profileMemory) } finally { $profileStream.Dispose() }
    $cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
    try { $cms.Decode($profileMemory.ToArray()) } finally { $profileMemory.Dispose() }
    $cms.CheckSignature($true)

    $xmlSettings = [System.Xml.XmlReaderSettings]::new()
    $xmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $xmlSettings.XmlResolver = $null
    $contentStream = [System.IO.MemoryStream]::new($cms.ContentInfo.Content)
    $xmlReader = [System.Xml.XmlReader]::Create($contentStream, $xmlSettings)
    try {
        $document = [System.Xml.Linq.XDocument]::Load($xmlReader)
    } finally {
        $xmlReader.Dispose()
        $contentStream.Dispose()
    }
    $dictionary = $document.Root.Element('dict')
    if ($null -eq $dictionary) { throw 'Profile plist dictionary is missing.' }
    $expiration = Find-PlistValue $dictionary 'ExpirationDate'
    $entitlements = Find-PlistValue $dictionary 'Entitlements'
    $packetTunnelListed = $false
    $wildcardPresent = $false
    if ($null -ne $entitlements) {
        $networkExtension = Find-PlistValue $entitlements 'com.apple.developer.networking.networkextension'
        if ($null -ne $networkExtension -and $networkExtension.Name.LocalName -eq 'array') {
            $values = @($networkExtension.Elements('string') | ForEach-Object { $_.Value })
            $packetTunnelListed = $values -contains 'packet-tunnel-provider'
            $wildcardPresent = $values -contains '*'
        }
    }
    $expiresAt = if ($null -ne $expiration) {
        [DateTimeOffset]::Parse($expiration.Value, [Globalization.CultureInfo]::InvariantCulture)
    } else { $null }
    # Do not return profile identifiers, device IDs, certificate data or keys.
    [pscustomobject]@{
        Role = $Role
        CMSSignatureIntact = $true
        PacketTunnelListed = $packetTunnelListed
        CapabilityWildcardNeedsReview = $wildcardPresent
        ProfileExpiredOrMissingExpiry = ($null -eq $expiresAt -or $expiresAt -le [DateTimeOffset]::UtcNow)
        ProfileExpiresUTC = if ($null -ne $expiresAt) { $expiresAt.UtcDateTime.ToString('o') } else { $null }
    }
}

$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $IPAPath).Path)
try {
    $mainProfiles = @($archive.Entries | Where-Object { $_.FullName -match '^Payload/[^/]+\.app/embedded\.mobileprovision$' })
    $tunnelProfiles = @($archive.Entries | Where-Object { $_.FullName -match '^Payload/[^/]+\.app/PlugIns/[^/]+\.appex/embedded\.mobileprovision$' })
    $summaries = @()
    if ($mainProfiles.Count -eq 1) { $summaries += Read-ProfileSummary $mainProfiles[0] 'App' }
    if ($tunnelProfiles.Count -eq 1) { $summaries += Read-ProfileSummary $tunnelProfiles[0] 'Tunnel' }
    $profilesPresent = $mainProfiles.Count -eq 1 -and $tunnelProfiles.Count -eq 1
    $candidate = $profilesPresent -and @($summaries | Where-Object {
        -not $_.PacketTunnelListed -or $_.ProfileExpiredOrMissingExpiry
    }).Count -eq 0
    [pscustomobject]@{
        CandidateForDeviceTest = $candidate
        BothProfilesPresent = $profilesPresent
        Profiles = $summaries
        StillUnverified = @('Apple trust chain', 'certificate revocation', 'device match', 'bundle ID match', 'signed binary entitlements', 'actual iPhone extension launch')
    } | ConvertTo-Json -Depth 4
    if (-not $candidate) { exit 2 }
} finally {
    $archive.Dispose()
}
