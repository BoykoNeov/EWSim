# julia.ps1 — invoke the project's pinned Julia without touching system PATH.
#
# Julia 1.11.9 is installed portably at the path below (not on PATH). All project
# scripts go through this wrapper so there is exactly one place to change if the
# install moves. Usage:  pwsh tools/julia.ps1 <args...>
$ErrorActionPreference = "Stop"
$Julia = "C:\Users\boiko\julia\julia-1.11.9\bin\julia.exe"
if (-not (Test-Path $Julia)) {
    Write-Error "Julia not found at $Julia — update tools/julia.ps1 if the install moved."
    exit 1
}
& $Julia @args
exit $LASTEXITCODE
