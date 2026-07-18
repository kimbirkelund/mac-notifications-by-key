#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build / test / run entry point for mac-notifications-by-key.

.DESCRIPTION
  Wraps SwiftPM (the nbk CLI + libraries) and the cucumber-js acceptance harness.
  The three test tiers (see docs/testing.md) are selected with -Kinds:
    Unit         swift test --filter NotificationCoreTests          (no AX)
    Integration  swift test --filter NotificationAXIntegrationTests  (needs AX trust)
    Acceptance   cucumber-js driving the compiled nbk binary         (needs AX trust)
  Integration/Acceptance are skipped (not failed) when Accessibility trust is absent.

  Lint (-DoLint) covers both code and docs:
    Swift  swift-format (.swift-format config)
    Docs   prettier (markdown, JSON, YAML incl. .github workflows, JS harness)
  Add -Fix to auto-format in place instead of only checking.

  Package (-DoPackage) builds a universal (arm64 + x86_64) release binary and
  produces dist/nbk-<version>-macos-universal.tar.gz plus a .sha256 sidecar - the
  artifacts the Homebrew formula consumes. Pass -Version to stamp the version into
  the binary (nbk --version); defaults to the committed "dev".

.EXAMPLE
  ./build.ps1 -DoBuild
  ./build.ps1 -DoTest -Kinds Unit
  ./build.ps1 -DoLint            # check only (fails on violations)
  ./build.ps1 -DoLint -Fix       # auto-format Swift + docs in place
  ./build.ps1 -DoPackage -Version 1.2.3
  ./build.ps1 -DoRun -RunArgs list,--wait,5
#>
[CmdletBinding()]
param(
  [switch]$DoInstall,
  [switch]$DoBuild,
  [switch]$DoTest,
  [switch]$DoLint,
  [switch]$Fix,
  [switch]$DoPackage,
  [switch]$DoRun,
  [string[]]$RunArgs = @(),
  [ValidateSet('All', 'Unit', 'Integration', 'Acceptance')]
  [string[]]$Kinds = @('All'),
  [ValidateSet('debug', 'release')]
  [string]$Configuration = 'debug',
  [switch]$Universal,
  [string]$Version,
  [switch]$SkipBuild,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Write-Step($msg) { if (-not $Quiet) { Write-Host "==> $msg" -ForegroundColor Cyan } }
function Write-Skip($msg) { Write-Host "--- skipped: $msg" -ForegroundColor Yellow }
function Invoke-Checked($file, [string[]]$argv)
{
  & $file @argv
  if ($LASTEXITCODE -ne 0) { throw "$file $($argv -join ' ') exited $LASTEXITCODE" }
}

# Packaging always means a universal release build.
if ($DoPackage)
{
  $Universal = $true
  $Configuration = 'release'
}

$binPath = if ($Universal)
{
  ".build/apple/Products/$((Get-Culture).TextInfo.ToTitleCase($Configuration))/nbk"
}
else { ".build/$Configuration/nbk" }

# Resolve which tiers to run.
$selected = if ($Kinds -contains 'All') { @('Unit', 'Integration', 'Acceptance') } else { $Kinds }

# nbk doctor exits 3 when Accessibility trust is missing; use it as the preflight.
function Test-AxTrust
{
  if (-not (Test-Path $binPath)) { return $false }
  & $binPath doctor *> $null
  return ($LASTEXITCODE -eq 0)
}

if ($DoInstall)
{
  Write-Step 'Resolving SwiftPM dependencies'
  Invoke-Checked 'swift' @('package', 'resolve')
  Write-Step 'Installing npm dependencies (acceptance harness)'
  Invoke-Checked 'npm' @('install')
}

$needBuild = $DoBuild -or $DoPackage -or ($DoTest -and -not $SkipBuild) -or ($DoRun -and -not $SkipBuild)
if ($needBuild)
{
  # Stamp the version into the binary (nbk --version) for this build, then restore
  # the working tree so the committed "dev" default is left untouched locally.
  $versionFile = Join-Path $PSScriptRoot 'Sources/nbk/Version.swift'
  $versionOriginal = $null
  if ($Version)
  {
    $versionOriginal = Get-Content -Raw -LiteralPath $versionFile
    [System.IO.File]::WriteAllText(
      $versionFile, "// Stamped by build.ps1 -Version.`nlet nbkVersion = `"$Version`"`n")
  }
  try
  {
    if ($Universal)
    {
      Write-Step "swift build (-c $Configuration, universal arm64+x86_64)"
      Invoke-Checked 'swift' @('build', '-c', $Configuration, '--arch', 'arm64', '--arch', 'x86_64')
    }
    else
    {
      Write-Step "swift build (-c $Configuration)"
      Invoke-Checked 'swift' @('build', '-c', $Configuration)
    }
  }
  finally
  {
    if ($null -ne $versionOriginal) { [System.IO.File]::WriteAllText($versionFile, $versionOriginal) }
  }
}

if ($DoTest)
{
  if ($selected -contains 'Unit')
  {
    Write-Step 'Unit tier (NotificationCoreTests)'
    Invoke-Checked 'swift' @('test', '--filter', 'NotificationCoreTests')
  }

  $needTrust = ($selected -contains 'Integration') -or ($selected -contains 'Acceptance')
  $trusted = if ($needTrust) { Test-AxTrust } else { $false }
  if ($needTrust -and -not $trusted)
  {
    Write-Host 'Accessibility trust not granted for this host (nbk doctor != 0).' -ForegroundColor Yellow
    Write-Host 'Grant it in System Settings > Privacy & Security > Accessibility, then rerun.' -ForegroundColor Yellow
  }

  if ($selected -contains 'Integration')
  {
    if ($trusted)
    {
      Write-Step 'AX-integration tier (NotificationAXIntegrationTests)'
      Invoke-Checked 'swift' @('test', '--filter', 'NotificationAXIntegrationTests')
    }
    else { Write-Skip 'Integration tier (no Accessibility trust)' }
  }

  if ($selected -contains 'Acceptance')
  {
    if ($trusted)
    {
      Write-Step 'Acceptance tier (cucumber-js, black-box nbk)'
      if (-not (Test-Path 'node_modules')) { Invoke-Checked 'npm' @('install') }
      $env:NBK_BIN = (Resolve-Path $binPath).Path
      Invoke-Checked 'npx' @('cucumber-js')
    }
    else { Write-Skip 'Acceptance tier (no Accessibility trust)' }
  }
}

if ($DoPackage)
{
  $pkgVersion = if ($Version) { $Version } else { 'dev' }
  $dist = Join-Path $PSScriptRoot 'dist'
  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  $tarName = "nbk-$pkgVersion-macos-universal.tar.gz"
  $tarPath = Join-Path $dist $tarName
  Write-Step "Packaging $tarName"
  Invoke-Checked 'tar' @('-czf', $tarPath, '-C', (Split-Path $binPath -Parent), 'nbk')
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $tarPath).Hash.ToLower()
  Set-Content -LiteralPath "$tarPath.sha256" -Value "$hash  $tarName"
  Write-Host "  sha256:   $hash"
  Write-Host "  artifact: $tarPath"
}

if ($DoLint)
{
  $swiftPaths = @('Package.swift', 'Sources', 'Tests')
  # Prefer the pinned local prettier (reproducible in CI); fall back to a global one.
  $localPrettier = Join-Path $PSScriptRoot 'node_modules/.bin/prettier'
  $prettier = if (Test-Path $localPrettier) { $localPrettier } else { 'prettier' }
  $psSettings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
  $psFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -File -Filter *.ps1 |
    Where-Object { $_.FullName -notmatch '[\\/](\.build|node_modules)[\\/]' }

  if ($Fix)
  {
    # swift-format ships with the Swift toolchain, only expected on macOS (C-5).
    if ($IsMacOS)
    {
      Write-Step 'swift-format (format in place)'
      Invoke-Checked 'swift' (@('format', 'format', '--in-place', '--recursive') + $swiftPaths)
    }
    else { Write-Skip 'swift-format (macOS only)' }
    Write-Step 'prettier (format docs in place)'
    Invoke-Checked $prettier @('--write', '--log-level', 'warn', '.')
    Write-Step 'PSScriptAnalyzer (format in place)'
    $settings = Import-PowerShellDataFile -Path $psSettings
    foreach ($file in $psFiles)
    {
      $original = Get-Content -Raw -LiteralPath $file.FullName
      $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settings
      if ($formatted -ne $original)
      {
        [System.IO.File]::WriteAllText($file.FullName, $formatted)
      }
    }
  }
  else
  {
    # swift-format ships with the Swift toolchain, only expected on macOS (C-5).
    if ($IsMacOS)
    {
      Write-Step 'swift-format (lint)'
      Invoke-Checked 'swift' (@('format', 'lint', '--strict', '--recursive') + $swiftPaths)
    }
    else { Write-Skip 'swift-format (macOS only)' }
    Write-Step 'prettier (check docs)'
    Invoke-Checked $prettier @('--check', '.')
    Write-Step 'PSScriptAnalyzer (lint)'
    $findings = $psFiles | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings $psSettings }
    if ($findings)
    {
      $findings |
        Format-Table -AutoSize RuleName, Severity, @{ N = 'File'; E = { Split-Path $_.ScriptPath -Leaf } }, Line, Message |
        Out-String |
        Write-Host
      throw "PSScriptAnalyzer reported $(@($findings).Count) issue(s)."
    }
  }
}

if ($DoRun)
{
  Write-Step "nbk $($RunArgs -join ' ')"
  Invoke-Checked $binPath $RunArgs
}

if (-not ($DoInstall -or $DoBuild -or $DoTest -or $DoLint -or $DoPackage -or $DoRun))
{
  Write-Host 'Nothing to do. Pass -DoInstall, -DoBuild, -DoTest, -DoLint, -DoPackage, or -DoRun. See -? for help.' -ForegroundColor Yellow
}
