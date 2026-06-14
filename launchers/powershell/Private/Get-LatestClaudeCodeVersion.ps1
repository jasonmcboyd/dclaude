function Get-LatestClaudeCodeVersion {
    <#
    .SYNOPSIS
        Resolves the latest published @anthropic-ai/claude-code version from the npm registry.
    .DESCRIPTION
        Queries the npm registry HTTP endpoint directly (no Node.js dependency) and returns
        the latest version string, or $null on any failure (network down, parse error). The
        result is cached in a host file under the user config directory so repeated calls
        within the TTL avoid network round-trips.

        This never throws and never Write-Errors on transient failures — callers decide how
        to handle a $null result (typically: keep using the existing runtime).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [int]$MaxAgeHours = 4,

        [Parameter()]
        [switch]$Force
    )

    $configDir = Join-Path $HOME '.dclaude'
    $cacheFile = Join-Path $configDir '.cc-latest-cache.json'

    # Try the cache first unless -Force was given.
    if (-not $Force -and (Test-Path -Path $cacheFile -PathType Leaf)) {
        try {
            $cache = Get-Content -Path $cacheFile -Raw | ConvertFrom-Json
            $hasVersion = $cache.PSObject.Properties['version'] -and $cache.version
            $hasTimestamp = $cache.PSObject.Properties['checkedAtUtc'] -and $cache.checkedAtUtc
            if ($hasVersion -and $hasTimestamp) {
                $checkedAt = [datetime]::Parse(
                    $cache.checkedAtUtc, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                $age = [datetime]::UtcNow - $checkedAt
                if ($age.TotalHours -lt $MaxAgeHours) {
                    Write-Verbose "dclaude: using cached latest Claude Code version ($($cache.version), age $([int]$age.TotalMinutes)m)"
                    return [string]$cache.version
                }
            }
        }
        catch {
            # Missing/corrupt cache is just a cache miss — fall through to the network query.
            Write-Verbose "dclaude: latest-version cache unreadable, querying registry: $_"
        }
    }

    # The scope separator '/' must be URL-encoded as %2F in the registry path.
    $url = 'https://registry.npmjs.org/@anthropic-ai%2Fclaude-code/latest'
    try {
        $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
        if (-not ($response.PSObject.Properties['version'] -and $response.version)) {
            Write-Verbose 'dclaude: registry response had no version field'
            return $null
        }
        $version = [string]$response.version
    }
    catch {
        Write-Verbose "dclaude: failed to query npm registry for latest Claude Code version: $_"
        return $null
    }

    # Best-effort cache write — failure here must not fail the call. -ErrorAction Stop
    # promotes non-terminating errors (e.g. $configDir exists as a non-directory) to the
    # catch so nothing leaks to the caller's error stream.
    try {
        if (-not (Test-Path -Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force -ErrorAction Stop | Out-Null
        }
        [PSCustomObject]@{
            version      = $version
            checkedAtUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Verbose "dclaude: could not write latest-version cache: $_"
    }

    return $version
}
