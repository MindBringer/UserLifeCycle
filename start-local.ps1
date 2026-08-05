$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$Arguments = @()
if ($args.Count -gt 0) { $Arguments += @('--port', $args[0]) }
if ($env:ULC_COMPANION_NO_BROWSER -eq '1') { $Arguments += '--no-browser' }
python3 tools/companion/server.py @Arguments
