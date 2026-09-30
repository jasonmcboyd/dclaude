$ErrorActionPreference = 'Stop'

if ($env:DCLAUDE_DNS_SUFFIX) {
    $suffixes = $env:DCLAUDE_DNS_SUFFIX -split ','
    Set-DnsClientGlobalSetting -SuffixSearchList $suffixes
}

& C:\nodejs\node.exe C:\app\server.js
exit $LASTEXITCODE
