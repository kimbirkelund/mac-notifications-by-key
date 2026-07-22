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
    Swift      swift-format (.swift-format config)
    Docs       prettier (markdown, JSON, YAML incl. .github workflows, JS harness)
    PowerShell PSScriptAnalyzer
    Workflows  actionlint (check-only; skipped if not installed)
  Add -Fix to auto-format in place instead of only checking.

  Package (-DoPackage) builds a universal (arm64 + x86_64) release binary and
  produces dist/nbk-<version>-macos-universal.tar.gz plus a .sha256 sidecar - the
  artifacts the Homebrew formula consumes. Pass -Version to stamp the version into
  the binary (nbk --version); defaults to the committed "dev".

  Release orchestration drives the GitHub workflows via gh and watches them (plus
  the runs they trigger) to completion. Both preflight that the working tree is
  clean and the current branch is in sync with its upstream:
    -DoPrepareRelease   dispatches prepare-rc.yml on main (add -Major to bump the
                        major version instead of the minor).
    -DoFinalizeRelease  finds the single outstanding rc/* branch (fails unless
                        exactly one) and dispatches tag-rc.yml on it.

.EXAMPLE
  ./build.ps1 -DoBuild
  ./build.ps1 -DoTest -Kinds Unit
  ./build.ps1 -DoLint            # check only (fails on violations)
  ./build.ps1 -DoLint -Fix       # auto-format Swift + docs in place
  ./build.ps1 -DoPackage -Version 1.2.3
  ./build.ps1 -DoRun -RunArgs list,--wait,5
  ./build.ps1 -DoPrepareRelease            # cut a release candidate (minor bump)
  ./build.ps1 -DoPrepareRelease -Major     # cut a release candidate (major bump)
  ./build.ps1 -DoFinalizeRelease           # finalize the outstanding rc/* branch
#>
[CmdletBinding(DefaultParameterSetName = 'None')]
param(
  [Parameter(ParameterSetName = 'Install')]
  [switch]$DoInstall,

  [Parameter(ParameterSetName = 'Build')]
  [switch]$DoBuild,

  [Parameter(ParameterSetName = 'Test')]
  [switch]$DoTest,

  [Parameter(ParameterSetName = 'Lint')]
  [switch]$DoLint,

  [Parameter(ParameterSetName = 'Package')]
  [switch]$DoPackage,

  [Parameter(ParameterSetName = 'Run')]
  [switch]$DoRun,

  [Parameter(ParameterSetName = 'PrepareRelease')]
  [switch]$DoPrepareRelease,

  [Parameter(ParameterSetName = 'FinalizeRelease')]
  [switch]$DoFinalizeRelease,

  [Parameter(ParameterSetName = 'Lint')]
  [switch]$Fix,

  [Parameter(ParameterSetName = 'PrepareRelease')]
  [switch]$Major,

  [Parameter(ParameterSetName = 'Run')]
  [string[]]$RunArgs = @(),

  [Parameter(ParameterSetName = 'Test')]
  [ValidateSet('All', 'Unit', 'Integration', 'Acceptance')]
  [string[]]$Kinds = @('All'),

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'Test')]
  [Parameter(ParameterSetName = 'Run')]
  [ValidateSet('debug', 'release')]
  [string]$Configuration = 'debug',

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'Test')]
  [Parameter(ParameterSetName = 'Run')]
  [switch]$Universal,

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'Package')]
  [string]$Version,

  [Parameter(ParameterSetName = 'Test')]
  [Parameter(ParameterSetName = 'Run')]
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

# --- release orchestration helpers (-DoPrepareRelease / -DoFinalizeRelease) ---

function Confirm-GhReady
{
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) not found on PATH.' }
  gh auth status *> $null
  if ($LASTEXITCODE -ne 0) { throw 'gh is not authenticated - run: gh auth login' }
}

# Release operations dispatch against main; refuse to run from any other branch so
# it's obvious what state is being released.
function Confirm-OnMain
{
  $branch = git rev-parse --abbrev-ref HEAD
  if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed (not a git repository?)' }
  if ($branch -ne 'main') { throw "Release operations must run from 'main' (currently on '$branch')." }
}

# Guard against operating on a dirty or out-of-sync tree, so a dispatched release
# never silently omits (or is surprised by) local/remote changes.
function Confirm-CleanAndSynced
{
  $status = git status --porcelain
  if ($LASTEXITCODE -ne 0) { throw 'git status failed (not a git repository?)' }
  if ($status) { throw "Working tree is not clean; commit or stash first:`n$status" }

  Write-Step 'Fetching origin'
  Invoke-Checked 'git' @('fetch', '--quiet', 'origin')

  $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $upstream) { throw 'Current branch has no upstream; push and track it first.' }
  $counts = (git rev-list --left-right --count '@{u}...HEAD').Trim() -split '\s+'
  $behind = [int]$counts[0]
  $ahead = [int]$counts[1]
  if ($behind -ne 0) { throw "Current branch is behind $upstream by $behind commit(s); pull first." }
  if ($ahead -ne 0) { throw "Current branch is ahead of $upstream by $ahead commit(s); push first." }
}

# Snapshot the ids of recent runs, so a dispatch's run (and the runs it triggers) can
# be identified as ids not present before it - avoids any wall-clock/timezone math.
function Get-RunIdSet
{
  $set = @{}
  gh run list --limit 100 --json databaseId --jq '.[].databaseId' |
    ForEach-Object { $set[[string]$_] = $true }
  return $set
}

# Watch a run to completion, then fail only on a genuine failure conclusion. Runs that
# conclude 'skipped' or 'neutral' (e.g. path-filtered or non-applicable triggered
# workflows like Auto-approve Renovate) are not failures. --exit-status can't be used:
# it treats skipped/neutral as failures too.
function Confirm-RunSucceeded([string]$id, [string]$name)
{
  gh run watch $id
  $conclusion = gh run view $id --json conclusion --jq '.conclusion'
  if ($conclusion -in @('failure', 'timed_out', 'startup_failure', 'cancelled', 'action_required'))
  {
    throw "Run $id ($name) concluded '$conclusion'."
  }
}

# Find and watch the run a dispatch created (a run id on $ref not in $baseline).
function Wait-DispatchedRun([string]$workflow, [string]$ref, [hashtable]$baseline)
{
  $id = $null
  for ($i = 0; $i -lt 30 -and -not $id; $i++)
  {
    Start-Sleep 2
    $ids = gh run list --workflow $workflow --branch $ref --limit 10 --json databaseId --jq '.[].databaseId'
    $id = $ids | Where-Object { -not $baseline.ContainsKey([string]$_) } | Select-Object -First 1
  }
  if (-not $id) { throw "Timed out finding the dispatched $workflow run." }
  Write-Step "Watching $workflow run $id"
  Confirm-RunSucceeded -id $id -name $workflow
}

# Watch every run not in $baseline (release.yml on the tag/branch push, PR CI, etc.)
# until they settle - three consecutive polls with no active run - so late-appearing
# triggered runs are still caught.
function Wait-TriggeredRun([hashtable]$baseline)
{
  $idle = 0
  for ($pass = 0; $pass -lt 240; $pass++)
  {
    $runs = gh run list --limit 50 --json 'databaseId,workflowName,status' | ConvertFrom-Json
    $active = @($runs |
        Where-Object { -not $baseline.ContainsKey([string]$_.databaseId) } |
        Where-Object { $_.status -in @('queued', 'in_progress', 'requested', 'waiting', 'pending') })
    if ($active.Count -gt 0)
    {
      $idle = 0
      foreach ($r in $active)
      {
        Write-Step "Watching triggered run: $($r.workflowName) [$($r.databaseId)]"
        Confirm-RunSucceeded -id $r.databaseId -name $r.workflowName
      }
    }
    else
    {
      $idle++
      if ($idle -ge 3) { return }
    }
    Start-Sleep 5
  }
  throw 'Timed out waiting for triggered runs to settle.'
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

    # Workflow linting; CI runs actionlint as its own job, so mirror it here (prettier
    # only checks YAML formatting, not Actions semantics). No autofix, so check-only.
    $workflowFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '.github/workflows') -Filter *.yml -File -ErrorAction SilentlyContinue)
    if ($workflowFiles)
    {
      if (Get-Command actionlint -ErrorAction SilentlyContinue)
      {
        Write-Step 'actionlint (workflows)'
        Invoke-Checked 'actionlint' $workflowFiles.FullName
      }
      else { Write-Skip 'actionlint (not installed - brew install actionlint)' }
    }
  }
}

if ($DoRun)
{
  Write-Step "nbk $($RunArgs -join ' ')"
  Invoke-Checked $binPath $RunArgs
}

# Cut a release candidate: dispatch prepare-rc.yml on main and watch it plus every
# run it triggers (the rc-branch prerelease, the bump PR CI) through to completion.
if ($DoPrepareRelease)
{
  Confirm-GhReady
  Confirm-OnMain
  Confirm-CleanAndSynced
  $baseline = Get-RunIdSet
  Write-Step "Dispatching prepare-rc.yml on main (major=$([bool]$Major))"
  $wfArgs = @('workflow', 'run', 'prepare-rc.yml', '--ref', 'main')
  if ($Major) { $wfArgs += @('-f', 'major=true') }
  Invoke-Checked 'gh' $wfArgs
  Wait-DispatchedRun -workflow 'prepare-rc.yml' -ref 'main' -baseline $baseline
  Wait-TriggeredRun -baseline $baseline
  Write-Step 'Pulling main (version bump landed remotely)'
  Invoke-Checked 'git' @('pull', '--ff-only', 'origin', 'main')
  Write-Step 'Prepare release complete.'
}

# Finalize the single outstanding rc/* branch: dispatch tag-rc.yml on it and watch it
# plus every run it triggers (the final release, the merge-back PR CI) to completion.
if ($DoFinalizeRelease)
{
  Confirm-GhReady
  Confirm-OnMain
  Confirm-CleanAndSynced
  $rcBranches = @(git ls-remote --heads origin 'refs/heads/rc/*' |
      ForEach-Object { ($_ -split '\s+')[1] -replace '^refs/heads/', '' })
  if ($rcBranches.Count -ne 1)
  {
    throw "Expected exactly one rc/* branch, found $($rcBranches.Count): $($rcBranches -join ', ')"
  }
  $rc = $rcBranches[0]
  $baseline = Get-RunIdSet
  Write-Step "Dispatching tag-rc.yml on $rc"
  Invoke-Checked 'gh' @('workflow', 'run', 'tag-rc.yml', '--ref', $rc)
  Wait-DispatchedRun -workflow 'tag-rc.yml' -ref $rc -baseline $baseline
  Wait-TriggeredRun -baseline $baseline
  Write-Step 'Pulling main (merge-back landed remotely)'
  Invoke-Checked 'git' @('pull', '--ff-only', 'origin', 'main')
  Write-Step 'Finalize release complete.'
}

if (-not ($DoInstall -or $DoBuild -or $DoTest -or $DoLint -or $DoPackage -or $DoRun -or $DoPrepareRelease -or $DoFinalizeRelease))
{
  Write-Host 'Nothing to do. Pass -DoInstall, -DoBuild, -DoTest, -DoLint, -DoPackage, -DoRun, -DoPrepareRelease, or -DoFinalizeRelease. See -? for help.' -ForegroundColor Yellow
}
