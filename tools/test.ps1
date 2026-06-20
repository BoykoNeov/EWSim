# test.ps1 — run the headless core test suite (the contract enforcer).
#   pwsh tools/test.ps1
$ErrorActionPreference = "Stop"
$Root  = Split-Path $PSScriptRoot -Parent
$Julia = "C:\Users\boiko\julia\julia-1.11.9\bin\julia.exe"
& $Julia --project="$Root\core" "$Root\core\test\runtests.jl"
exit $LASTEXITCODE
