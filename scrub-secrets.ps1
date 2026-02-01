<#
PowerShell script to remove secrets from git history and force-push cleaned branch.
Run from repository root. Review `secrets-replace.txt` before running.
Usage: Right-click -> "Run with PowerShell" or in PowerShell: `.\\scrub-secrets.ps1`
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ErrAndExit($msg){ Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Ensure repo root
if (-not (Test-Path -Path .git)) { Write-ErrAndExit "This does not look like a git repository. Run this from the repo root." }

Write-Host "WARNING: This script rewrites git history and will force-push to 'main'." -ForegroundColor Yellow
Write-Host "It will create a backup branch before making changes.
" -ForegroundColor Yellow

$confirm = Read-Host "Type YES to continue"
if ($confirm -ne 'YES') { Write-Host "Aborting."; exit 0 }

# Ensure working tree clean
$status = git status --porcelain
if ($status) {
  Write-Host "You have uncommitted changes. Please commit or stash them before proceeding." -ForegroundColor Red
  Write-Host $status
  exit 1
}

# Create backup branch
$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$backup = "pre-scrub-backup-$ts"
Write-Host "Creating backup branch '$backup'..."
git branch $backup

# Install git-filter-repo if needed
Write-Host "Ensuring git-filter-repo is installed (via pip)..."
$pythonCmd = 'python'
try {
  & $pythonCmd -V > $null 2>&1
} catch {
  # try py launcher on Windows
  $pythonCmd = 'py -3'
  try { & $pythonCmd -V > $null 2>&1 } catch { Write-ErrAndExit "Python not found. Install Python 3 and ensure 'python' or 'py' is on PATH." }
}

Write-Host "Installing/Upgrading git-filter-repo..."
& $pythonCmd -m pip install --upgrade git-filter-repo

# confirm secrets-replace.txt exists
$replaceFile = Join-Path (Get-Location) 'secrets-replace.txt'
if (-not (Test-Path $replaceFile)) { Write-ErrAndExit "Replace file 'secrets-replace.txt' not found in repo root. Edit or provide it before running." }

# Run filter-repo (this rewrites history)
Write-Host "Running git-filter-repo (this may take a few moments)..."
# Use python -m git_filter_repo for reliability
& $pythonCmd -m git_filter_repo --force --replace-text $replaceFile

# Verify no common secret patterns remain
Write-Host "Verifying repository for common secret patterns..."
$patterns = @('sk_test_','sk_live_','pk_test_','pk_live_','whsec_','re_')
$found = $false
foreach ($p in $patterns) {
  try {
    $out = git grep -n --no-color -- "${p}" 2>$null
    if ($out) {
      Write-Host "Matches for pattern '$p' found:" -ForegroundColor Red
      Write-Host $out
      $found = $true
    }
  } catch { }
}

if ($found) {
  Write-Host "One or more secret patterns still exist in the repo. Review the output above and fix manually." -ForegroundColor Red
  Write-Host "A backup branch named '$backup' contains the pre-scrub history." -ForegroundColor Yellow
  exit 2
}

# Force-push cleaned branch to remote main
Write-Host "No matches found. Force-pushing cleaned branch to origin/main..." -ForegroundColor Green
try {
  git push origin HEAD:main --force
  Write-Host "Push completed. Repository history rewritten on remote 'main'." -ForegroundColor Green
} catch {
  Write-Host "Push failed. GitHub may still block the push (push-protection). You can follow the GitHub unblock URL from the push error to allow the specific secret while remediating or contact repo admins." -ForegroundColor Red
  exit 3
}

Write-Host "DONE: History cleaned and pushed." -ForegroundColor Green
Write-Host "IMPORTANT: Rotate/revoke any leaked API keys (Stripe, Resend, etc.) immediately via their dashboards." -ForegroundColor Yellow

exit 0
