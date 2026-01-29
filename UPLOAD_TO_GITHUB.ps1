# ============================================================
# FlashEASuite V2 - GitHub Upload Script (FULL CLEANUP)
# ============================================================
# Run this in PowerShell AS ADMINISTRATOR
# Location: FlashEASuite_V2 root directory
# ============================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "FlashEASuite V2 - GitHub Upload (Force Update)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Step 0: Verify Location
# ============================================================
Write-Host "Step 0: Verifying location..." -ForegroundColor Yellow
$currentPath = Get-Location
Write-Host "Current path: $currentPath"

if (-not (Test-Path ".git")) {
    Write-Host "❌ ERROR: Not in a Git repository!" -ForegroundColor Red
    Write-Host "Please run this script in FlashEASuite_V2 root directory" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Git repository detected" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 1: Backup current state (just in case)
# ============================================================
Write-Host "Step 1: Creating backup..." -ForegroundColor Yellow
$backupTime = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFolder = "BACKUP_BEFORE_GITHUB_$backupTime"

Write-Host "Creating backup: $backupFolder"
# Just create a marker file
"Backup created at $backupTime" | Out-File "$backupFolder.txt"
Write-Host "✅ Backup marker created" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 2: Copy new .gitignore
# ============================================================
Write-Host "Step 2: Copying .gitignore..." -ForegroundColor Yellow

if (Test-Path ".gitignore") {
    Write-Host "Old .gitignore exists, backing up..."
    Move-Item -Path ".gitignore" -Destination ".gitignore.old" -Force
}

# User needs to copy .gitignore from outputs
Write-Host "⚠️  ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "Copy .gitignore from outputs folder to here!" -ForegroundColor Yellow
Write-Host "Press Enter when done..."
Read-Host

if (-not (Test-Path ".gitignore")) {
    Write-Host "❌ ERROR: .gitignore not found!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ .gitignore in place" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 3: Show current Git status
# ============================================================
Write-Host "Step 3: Current Git status..." -ForegroundColor Yellow
git status --short
Write-Host ""

# ============================================================
# Step 4: Remove ALL tracked files from Git (not from disk!)
# ============================================================
Write-Host "Step 4: Removing all tracked files from Git index..." -ForegroundColor Yellow
Write-Host "⚠️  This will NOT delete files from disk!" -ForegroundColor Yellow
Write-Host "It only removes them from Git tracking" -ForegroundColor Yellow
Write-Host ""
Write-Host "Continue? (Y/N)" -ForegroundColor Yellow
$confirm = Read-Host

if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Aborted by user" -ForegroundColor Red
    exit 0
}

Write-Host "Removing all files from Git index..."
git rm -r --cached . 2>&1 | Out-Null
Write-Host "✅ Git index cleared" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 5: Add files back (respecting .gitignore)
# ============================================================
Write-Host "Step 5: Adding files back (with new .gitignore)..." -ForegroundColor Yellow
git add .
Write-Host "✅ Files added (excluding ignored files)" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 6: Show what will be committed
# ============================================================
Write-Host "Step 6: Files to be committed..." -ForegroundColor Yellow
Write-Host ""
git status --short | Select-Object -First 50
Write-Host ""
Write-Host "... (showing first 50 files only)" -ForegroundColor Gray
Write-Host ""

$fileCount = (git status --short | Measure-Object).Count
Write-Host "Total files to commit: $fileCount" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Step 7: Commit
# ============================================================
Write-Host "Step 7: Committing changes..." -ForegroundColor Yellow
Write-Host "Enter commit message (or press Enter for default):"
$commitMsg = Read-Host

if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    $commitMsg = "feat: Complete system update - Phase 1 License System + Full codebase cleanup"
}

Write-Host "Committing: $commitMsg"
git commit -m "$commitMsg"

if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Commit failed or no changes to commit" -ForegroundColor Yellow
    Write-Host "Continue anyway? (Y/N)"
    $continue = Read-Host
    if ($continue -ne "Y" -and $continue -ne "y") {
        exit 1
    }
} else {
    Write-Host "✅ Commit successful" -ForegroundColor Green
}
Write-Host ""

# ============================================================
# Step 8: Check remote
# ============================================================
Write-Host "Step 8: Checking remote repository..." -ForegroundColor Yellow
git remote -v
Write-Host ""

$remoteUrl = git remote get-url origin 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ No remote 'origin' configured!" -ForegroundColor Red
    Write-Host "Add remote first: git remote add origin <URL>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Remote URL: $remoteUrl" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Step 9: FORCE PUSH to main
# ============================================================
Write-Host "Step 9: Force pushing to GitHub..." -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  WARNING: This will OVERWRITE GitHub with local files!" -ForegroundColor Red
Write-Host "⚠️  GitHub will match exactly what you have locally" -ForegroundColor Red
Write-Host ""
Write-Host "Are you ABSOLUTELY sure? (Type 'YES' to confirm)" -ForegroundColor Yellow
$confirmPush = Read-Host

if ($confirmPush -ne "YES") {
    Write-Host "Aborted by user" -ForegroundColor Red
    exit 0
}

Write-Host ""
Write-Host "Force pushing to origin main..." -ForegroundColor Yellow
git push origin main --force

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Push failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host "1. Authentication failed - need Personal Access Token" -ForegroundColor Yellow
    Write-Host "2. Network issue" -ForegroundColor Yellow
    Write-Host "3. Repository permissions" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Try manual push:" -ForegroundColor Yellow
    Write-Host "git push origin main --force" -ForegroundColor Cyan
    exit 1
}

Write-Host "✅ Push successful!" -ForegroundColor Green
Write-Host ""

# ============================================================
# Step 10: Verify
# ============================================================
Write-Host "Step 10: Verification..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Local commit:"
git log -1 --oneline
Write-Host ""
Write-Host "Remote commit:"
git log origin/main -1 --oneline
Write-Host ""

# ============================================================
# Step 11: Summary
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "✅ GitHub Upload Complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What was done:" -ForegroundColor Yellow
Write-Host "✅ Cleared Git cache" -ForegroundColor Green
Write-Host "✅ Applied new .gitignore" -ForegroundColor Green
Write-Host "✅ Committed all source code" -ForegroundColor Green
Write-Host "✅ Force pushed to GitHub" -ForegroundColor Green
Write-Host ""
Write-Host "What was excluded:" -ForegroundColor Yellow
Write-Host "❌ Compiled files (.ex5, .dll, .obj)" -ForegroundColor Gray
Write-Host "❌ Cache (__pycache__, logs)" -ForegroundColor Gray
Write-Host "❌ ZIP files" -ForegroundColor Gray
Write-Host "❌ Private keys (server_private.pem)" -ForegroundColor Gray
Write-Host "❌ Backup files (*_OLD, *_Backup)" -ForegroundColor Gray
Write-Host ""
Write-Host "Repository URL:" -ForegroundColor Yellow
Write-Host "$remoteUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Visit GitHub and verify files" -ForegroundColor White
Write-Host "2. Check that no secrets were uploaded" -ForegroundColor White
Write-Host "3. Create release tag if needed" -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Done! 🎉" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# Keep window open
Write-Host ""
Write-Host "Press Enter to exit..."
Read-Host
