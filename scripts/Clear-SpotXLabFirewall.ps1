param(
    [string]$Profile = 'default'
)

$ErrorActionPreference = 'Stop'

$launcher = Join-Path $PSScriptRoot 'Start-SpotXLab-OneClick.ps1'
& $launcher -Profile $Profile -CleanupNetworkRules
