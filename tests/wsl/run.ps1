<#
.SYNOPSIS
  Windows PowerShell wrapper for WSL test suite (imagedecoder-houri).

.DESCRIPTION
  Runs the bash suite `run_all.sh` via WSL - the single supported path for
  Windows native builds. Mirrors `scripts/wsl-tests/run.ps1` but lives
  colocated with the tests for submodule-standalone use.

  Why PowerShell + WSL? The native Gradle/AGP build invokes
  `C:/.../cmake.exe` on Windows but every ExternalProject step is
  `wsl /usr/bin/bash .../meson_helper.sh`. Running the tests through
  `wsl bash` validates the exact same path the build uses, without requiring
  Git Bash or MSYS.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File external\imagedecoder-houri\tests\wsl\run.ps1
  pwsh -File external/imagedecoder-houri/tests/wsl/run.ps1 -Verbose
  .\run.ps1 -Suite test_meson_helper
  .\run.ps1 -WhatIf

.PARAMETER Suite
  Optional single suite to run (e.g. test_meson_helper, test_to_msys_path).
  Without it, runs all suites via run_all.sh.

.PARAMETER WhatIf
  Print the wsl command that would be run without executing.

.PARAMETER Verbose
  Forwarded to Write-Verbose.

.NOTES
  Exit code mirrors run_all.sh: 0 all passed, 1 failures, 2 environment.
  No Gradle or Android SDK required.
#>
param(
  [string]$Suite,
  [switch]$WhatIf
)
# Fallback for powershell -File with hyphenated script path where named params become positional
$needsFallback = $false
if ($Suite -like "-*") { $needsFallback = $true }
elseif (-not $WhatIf -and $args -contains "-WhatIf") { $needsFallback = $true }
elseif ($Suite -and $args.Count -gt 0 -and $args[0] -like "-*") { $needsFallback = $true }
if ($needsFallback -or (-not $Suite -and -not $WhatIf -and $args.Count -gt 0)) {
  $wasSuite = $Suite
  $Suite = $null; $WhatIf = $false
  if ($wasSuite -eq "-WhatIf") { $WhatIf = $true }
  elseif ($wasSuite -and $wasSuite -notlike "-*" ) { $Suite = $wasSuite }
  for ($i=0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Suite" -and $i+1 -lt $args.Count) { $Suite = $args[$i+1]; $i++ }
    elseif ($args[$i] -eq "-WhatIf") { $WhatIf = $true }
    elseif ($args[$i] -notlike "-*" -and -not $Suite) { $Suite = $args[$i] }
  }
  if ($Suite -like "-*") { $Suite = $null }
  if ($wasSuite -eq "-WhatIf") { $WhatIf = $true }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  $here = $PSScriptRoot
  # PSScriptRoot = .../external/imagedecoder-houri/tests/wsl
  # repo root is 4 levels up: wsl -> tests -> imagedecoder-houri -> external -> repo
  $candidate = Resolve-Path (Join-Path $here "..\..\..\..") -ErrorAction Stop
  return $candidate.Path
}

function Find-WslExe {
  $candidates = @(
    "$env:SystemRoot\System32\wsl.exe",
    "$env:SystemRoot\Sysnative\wsl.exe",
    "C:\Windows\System32\wsl.exe",
    "C:\Windows\Sysnative\wsl.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  $viaPath = Get-Command wsl -ErrorAction SilentlyContinue
  if ($viaPath) { return $viaPath.Source }
  return $null
}

function Convert-ToWslPath {
  param([string]$WinPath)
  # Prefer wsl wslpath if available; fallback to manual /mnt/<drive>/.
  # This is the PowerShell mirror of CMake's to_msys_path().
  $p = $WinPath -replace '\\','/'
  if ($p -match '^/mnt/[a-z]/') { return $p }
  if ($p -match '^/[a-z]/') { return ($p -replace '^/([a-z])/', '/mnt/$1/') }
  if ($p -match '^/[^/]') { return $p }
  if ($p -match '^([A-Za-z]):/(.*)') {
    $drive = $Matches[1].ToLower()
    $rest = $Matches[2]
    return "/mnt/$drive/$rest"
  }
  return $p
}

$repoRoot = Resolve-RepoRoot
$wslExe = Find-WslExe
if (-not $wslExe) {
  Write-Host "ERROR: wsl.exe not found. WSL is required on Windows for imagedecoder builds." -ForegroundColor Red
  Write-Host "  Searched: C:\Windows\System32\wsl.exe, C:\Windows\Sysnative\wsl.exe, and PATH" -ForegroundColor Yellow
  Write-Host "  Install: https://aka.ms/wsl  (elevated PowerShell: wsl --install)" -ForegroundColor Yellow
  Write-Host "  Verify: wsl --status  and  wsl bash -c 'meson --version'" -ForegroundColor Yellow
  exit 2
}

Write-Verbose "Repo root: $repoRoot"
Write-Verbose "WSL: $wslExe"

# Resolve the bash suite path(s) as WSL /mnt/... paths
$wslTestsDirWin = Join-Path $repoRoot "external\imagedecoder-houri\tests\wsl"
$wslTestsDir = Convert-ToWslPath $wslTestsDirWin
$runAllWsl = "$wslTestsDir/run_all.sh"

# Validate WSL side
$probe = & $wslExe bash -c "test -f '$runAllWsl' && echo FOUND || echo MISSING" 2>&1
if ($probe -notmatch "FOUND") {
  Write-Host "ERROR: run_all.sh not found at WSL path $runAllWsl" -ForegroundColor Red
  Write-Host "  Windows path: $wslTestsDirWin\run_all.sh" -ForegroundColor Yellow
  exit 2
}

# Optional single-suite mode
$targetWsl = $runAllWsl
$targetLabel = "run_all.sh (all suites)"
if ($Suite) {
  $suiteName = $Suite
  if (-not $suiteName.EndsWith(".sh")) { $suiteName = "$suiteName.sh" }
  $candidateWin = Join-Path $wslTestsDirWin $suiteName
  $candidateWsl = Convert-ToWslPath $candidateWin
  $check = & $wslExe bash -c "test -f '$candidateWsl' && echo FOUND || echo MISSING" 2>&1
  if ($check -notmatch "FOUND") {
    # also try cmake suite
    $cmakeCandidate = Join-Path $wslTestsDirWin "test_cmake_to_msys.cmake"
    $cmakeWsl = Convert-ToWslPath $cmakeCandidate
    $check2 = & $wslExe bash -c "test -f '$candidateWsl' -o -f '$cmakeWsl' && echo FOUND || echo MISSING" 2>&1
    if ($check2 -notmatch "FOUND") {
      Write-Host "ERROR: suite '$Suite' not found. Available:" -ForegroundColor Red
      & $wslExe bash -c "ls -1 '$wslTestsDir'/test_*.sh '$wslTestsDir'/test_*.cmake 2>/dev/null" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
      exit 2
    }
  }
  if ($suiteName -like "*.cmake") {
    $targetWsl = $candidateWsl
    $targetLabel = $suiteName
  } else {
    $targetWsl = $candidateWsl
    $targetLabel = $suiteName
  }
}

# Build the wsl bash command
if ($targetWsl -like "*.cmake") {
  $wslCmd = "cmake -P '$targetWsl'"
} else {
  $wslCmd = "bash '$targetWsl'"
}

Write-Host "WSL Tests - imagedecoder-houri" -ForegroundColor Cyan
Write-Host "Host: Windows $([Environment]::OSVersion.Version) | WSL: $wslExe" -ForegroundColor Cyan
Write-Host "Suite: $targetLabel" -ForegroundColor Cyan
Write-Host "WSL cmd: wsl bash -c '$wslCmd'" -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
  Write-Host "[WhatIf] Would run: $wslExe bash -c '$wslCmd'" -ForegroundColor Yellow
  exit 0
}

# Execute via WSL and mirror exit code
& $wslExe bash -c $wslCmd
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
  Write-Host "ALL TESTS PASSED (via PowerShell wrapper)" -ForegroundColor Green
} else {
  Write-Host "SOME TESTS FAILED (exit $exitCode) - see above" -ForegroundColor Red
  Write-Host "Fix hints:" -ForegroundColor Yellow
  Write-Host "  rm -rf external\imagedecoder-houri\library\.cxx  (from PowerShell: Remove-Item -Recurse -Force external\imagedecoder-houri\library\.cxx)" -ForegroundColor Yellow
  Write-Host "  wsl bash -c 'sudo apt update && sudo apt install -y build-essential autoconf automake libtool pkg-config meson ninja-build cmake python3'" -ForegroundColor Yellow
}
exit $exitCode
