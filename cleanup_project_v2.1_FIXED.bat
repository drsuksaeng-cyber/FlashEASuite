@echo off
REM ========================================================================
REM FlashEASuite V2 - COMPLETE Project Cleanup Script v2.1 (FIXED)
REM ========================================================================
REM Purpose: 
REM   1. Clean up junk files completely
REM   2. Organize documentation
REM   3. Create verification file
REM   4. Prepare for Python module installation
REM Date: December 6, 2025
REM Version: 2.1 (Fixed folder names)
REM ========================================================================

echo.
echo ========================================================================
echo FlashEASuite V2 - COMPLETE Project Cleanup Script v2.1
echo ========================================================================
echo.
echo This script will:
echo   1. Delete junk files (.git, test files, empty files)
echo   2. Organize documentation in docs/
echo   3. Create VERIFICATION.txt for inspection
echo   4. Prepare for Python module installation
echo.
echo WARNING: This operation cannot be undone!
echo.
pause

REM ========================================================================
REM STEP 0: CREATE VERIFICATION FILE
REM ========================================================================

echo.
echo ========================================================================
echo STEP 0: Creating VERIFICATION.txt...
echo ========================================================================

echo FlashEASuite V2 - Cleanup Verification Report > VERIFICATION.txt
echo Date: %date% %time% >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo BEFORE CLEANUP - DIRECTORY LISTING: >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
dir /s /b >> VERIFICATION.txt
echo. >> VERIFICATION.txt

echo [OK] Created VERIFICATION.txt (before cleanup)

REM ========================================================================
REM STEP 1: DELETE .GIT FOLDER
REM ========================================================================

echo.
echo ========================================================================
echo STEP 1: Deleting .git folder...
echo ========================================================================

if exist ".git" (
    echo [DELETE] .git\ folder...
    rmdir /s /q ".git"
    if not exist ".git" (
        echo [OK] Deleted .git\ folder
    ) else (
        echo [ERROR] Failed to delete .git\ folder
    )
) else (
    echo [SKIP] .git\ folder not found
)

REM ========================================================================
REM STEP 2: DELETE TEST FILES (EXCEPT test_feedback_loop.py)
REM ========================================================================

echo.
echo ========================================================================
echo STEP 2: Deleting test files...
echo ========================================================================

REM Delete test MQL5 files
echo.
echo [DELETE] Test MQL5 files...
for %%f in (
    "03_Trader\TestNetworkingLayer.mq5"
    "03_Trader\TestTradeReporter.mq5"
    "03_Trader\files\TestNetworkingLayer.mq5"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete test Python files in files/ folder
echo.
echo [DELETE] Test Python files in files/...
if exist "03_Trader\files\test_brain_server.py" (
    del /q "03_Trader\files\test_brain_server.py"
    echo [OK] Deleted 03_Trader\files\test_brain_server.py
)

REM Note: KEEP test_feedback_loop.py
echo.
echo [KEEP] 02_ProgramB_Brain_Py\test_feedback_loop.py (PRESERVED)

REM ========================================================================
REM STEP 3: DELETE EMPTY FILES AND PYCACHE
REM ========================================================================

echo.
echo ========================================================================
echo STEP 3: Deleting empty files and __pycache__...
echo ========================================================================

if exist "03_Trader\Config\Settings.mqh" (
    echo [DELETE] 03_Trader\Config\Settings.mqh (empty file)
    del /q "03_Trader\Config\Settings.mqh"
    echo [OK] Deleted Settings.mqh
)

REM Delete Config folder if empty
if exist "03_Trader\Config" (
    rmdir "03_Trader\Config" 2>nul
    if not exist "03_Trader\Config" (
        echo [OK] Deleted empty Config\ folder
    )
)

REM Delete __pycache__ folders
echo.
echo [DELETE] Python cache folders...
for /d /r %%d in (__pycache__) do (
    if exist "%%d" (
        rmdir /s /q "%%d"
        echo [OK] Deleted %%d
    )
)

REM ========================================================================
REM STEP 4: DELETE DUPLICATE FILES/ FOLDER
REM ========================================================================

echo.
echo ========================================================================
echo STEP 4: Deleting duplicate files/ folder...
echo ========================================================================

if exist "03_Trader\files" (
    echo [DELETE] 03_Trader\files\ folder (contains duplicates)...
    rmdir /s /q "03_Trader\files"
    if not exist "03_Trader\files" (
        echo [OK] Deleted files\ folder
    ) else (
        echo [ERROR] Failed to delete files\ folder
    )
) else (
    echo [SKIP] files\ folder not found
)

REM ========================================================================
REM STEP 5: ORGANIZE DOCUMENTATION
REM ========================================================================

echo.
echo ========================================================================
echo STEP 5: Organizing documentation...
echo ========================================================================

REM Check if docs/ exists (it should)
if not exist "docs" (
    echo [CREATE] docs\ folder...
    mkdir "docs"
    mkdir "docs\installation"
    mkdir "docs\fixes"
    mkdir "docs\guides"
    mkdir "docs\summaries"
    mkdir "docs\archive"
    echo [OK] Created docs\ folder structure
)

REM Move ProtocolSpecs.md from 00_Common to docs/guides
echo.
echo [MOVE] Documentation files...
if exist "00_Common\ProtocolSpecs.md" (
    move /y "00_Common\ProtocolSpecs.md" "docs\guides\" >nul 2>&1
    echo [OK] Moved 00_Common\ProtocolSpecs.md to docs\guides\
)

REM Delete 00_Common folder if empty
if exist "00_Common\Keys" (
    rmdir /s /q "00_Common\Keys" 2>nul
)
if exist "00_Common" (
    rmdir "00_Common" 2>nul
    if not exist "00_Common" (
        echo [OK] Deleted empty 00_Common\ folder
    )
)

REM Move new chat4.txt to archive (if exists)
if exist "docs\archive\new chat4.txt" (
    echo [OK] new chat4.txt already in archive
) else if exist "new chat4.txt" (
    move /y "new chat4.txt" "docs\archive\" >nul 2>&1
    echo [OK] Moved new chat4.txt to archive
)

REM Move FINAL_SOLUTION_COMPLETE.md to summaries (if in root)
if exist "FINAL_SOLUTION_COMPLETE.md" (
    move /y "FINAL_SOLUTION_COMPLETE.md" "docs\summaries\" >nul 2>&1
    echo [OK] Moved FINAL_SOLUTION_COMPLETE.md to summaries
)

REM ========================================================================
REM STEP 6: VERIFY PYTHON_STRATEGY AND MQL MODULES EXIST
REM ========================================================================

echo.
echo ========================================================================
echo STEP 6: Verifying new module folders...
echo ========================================================================

echo.
echo [CHECK] Verifying new module folders...

set MODULES_OK=1

if exist "python_strategy" (
    echo [OK] python_strategy\ folder exists
) else (
    echo [WARN] python_strategy\ folder NOT FOUND
    set MODULES_OK=0
)

if exist "mql_protocol" (
    echo [OK] mql_protocol\ folder exists
) else (
    echo [WARN] mql_protocol\ folder NOT FOUND
    set MODULES_OK=0
)

if exist "mql_grid" (
    echo [OK] mql_grid\ folder exists
) else (
    echo [WARN] mql_grid\ folder NOT FOUND
    set MODULES_OK=0
)

if %MODULES_OK%==0 (
    echo.
    echo [WARNING] Some module folders are missing!
    echo Please extract FlashEA_Refactored_Complete_v2.zip first.
)

REM ========================================================================
REM STEP 7: CREATE INSTALLATION FOLDERS (CRITICAL FIX!)
REM ========================================================================

echo.
echo ========================================================================
echo STEP 7: Preparing installation folders... (CRITICAL)
echo ========================================================================

REM Python core/strategy folder (FIXED: Use correct folder name)
if not exist "02_ProgramB_Brain_Py\core\strategy" (
    echo [CREATE] 02_ProgramB_Brain_Py\core\strategy\
    mkdir "02_ProgramB_Brain_Py\core\strategy"
    echo [OK] Created strategy\ folder (ready for Python modules)
) else (
    echo [SKIP] strategy\ folder already exists
)

REM MQL5 Protocol folder
if not exist "Include\Network\Protocol" (
    echo [CREATE] Include\Network\Protocol\
    mkdir "Include\Network\Protocol"
    echo [OK] Created Protocol\ folder (ready for MQL5 Protocol modules)
) else (
    echo [SKIP] Protocol\ folder already exists
)

REM MQL5 Grid folder
if not exist "Include\Logic\Grid" (
    echo [CREATE] Include\Logic\Grid\
    mkdir "Include\Logic\Grid"
    echo [OK] Created Grid\ folder (ready for MQL5 Grid modules)
) else (
    echo [SKIP] Grid\ folder already exists
)

REM ========================================================================
REM STEP 8: UPDATE VERIFICATION FILE (AFTER CLEANUP)
REM ========================================================================

echo.
echo ========================================================================
echo STEP 8: Updating VERIFICATION.txt...
echo ========================================================================

echo. >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo AFTER CLEANUP - DIRECTORY LISTING: >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
dir /s /b >> VERIFICATION.txt

echo. >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo CLEANUP ACTIONS PERFORMED: >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo [X] Deleted .git\ folder >> VERIFICATION.txt
echo [X] Deleted test files (except test_feedback_loop.py) >> VERIFICATION.txt
echo [X] Deleted empty Settings.mqh >> VERIFICATION.txt
echo [X] Deleted __pycache__ folders >> VERIFICATION.txt
echo [X] Deleted duplicate files\ folder >> VERIFICATION.txt
echo [X] Organized documentation in docs\ >> VERIFICATION.txt
echo [X] Moved ProtocolSpecs.md to docs\guides\ >> VERIFICATION.txt
echo [X] Deleted 00_Common\ folder >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo FOLDERS CREATED FOR INSTALLATION: >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo [X] 02_ProgramB_Brain_Py\core\strategy\ >> VERIFICATION.txt
echo [X] Include\Network\Protocol\ >> VERIFICATION.txt
echo [X] Include\Logic\Grid\ >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo NEXT STEPS - INSTALLATION: >> VERIFICATION.txt
echo ======================================== >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo Step 3: Install Python Modules >> VERIFICATION.txt
echo -------------------------------- >> VERIFICATION.txt
echo   xcopy /s /y python_strategy\* 02_ProgramB_Brain_Py\core\strategy\ >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo Step 4A: Install MQL5 Protocol Modules >> VERIFICATION.txt
echo -------------------------------- >> VERIFICATION.txt
echo   copy /y mql_protocol\Definitions.mqh Include\Network\Protocol\ >> VERIFICATION.txt
echo   copy /y mql_protocol\Serialization.mqh Include\Network\Protocol\ >> VERIFICATION.txt
echo   copy /y mql_protocol\Protocol.mqh Include\Network\ >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo Step 4B: Install MQL5 Grid Modules >> VERIFICATION.txt
echo -------------------------------- >> VERIFICATION.txt
echo   copy /y mql_grid\GridConfig.mqh Include\Logic\Grid\ >> VERIFICATION.txt
echo   copy /y mql_grid\GridState.mqh Include\Logic\Grid\ >> VERIFICATION.txt
echo   copy /y mql_grid\GridCore.mqh Include\Logic\Grid\ >> VERIFICATION.txt
echo   copy /y mql_grid\Strategy_Grid.mqh Include\Logic\ >> VERIFICATION.txt
echo. >> VERIFICATION.txt
echo Step 5: Verify Installation >> VERIFICATION.txt
echo -------------------------------- >> VERIFICATION.txt
echo   Python: python -c "from core.strategy import create_strategy_engine_threaded" >> VERIFICATION.txt
echo   MQL5: Compile ProgramC_Trader.mq5 in MetaEditor >> VERIFICATION.txt
echo. >> VERIFICATION.txt

echo [OK] Updated VERIFICATION.txt with after-cleanup state

REM ========================================================================
REM STEP 9: FINAL SUMMARY
REM ========================================================================

echo.
echo ========================================================================
echo CLEANUP COMPLETE!
echo ========================================================================
echo.
echo Summary of actions:
echo   [X] Deleted .git\ folder
echo   [X] Deleted test files (kept test_feedback_loop.py)
echo   [X] Deleted empty Settings.mqh
echo   [X] Deleted __pycache__ folders
echo   [X] Deleted duplicate files\ folder
echo   [X] Organized documentation
echo   [X] Created installation folders
echo   [X] Created VERIFICATION.txt
echo.
echo Installation folders created:
echo   [OK] 02_ProgramB_Brain_Py\core\strategy\
echo   [OK] Include\Network\Protocol\
echo   [OK] Include\Logic\Grid\
echo.
echo Next steps:
echo   1. Review VERIFICATION.txt
echo   2. Run install_modules.bat (or manual install)
echo.
echo Files ready for installation:
if exist "python_strategy" (
    echo   [OK] python_strategy\ ^(5 files^)
) else (
    echo   [MISSING] python_strategy\ - Extract FlashEA_Refactored_Complete_v2.zip
)
if exist "mql_protocol" (
    echo   [OK] mql_protocol\ ^(3 files^)
) else (
    echo   [MISSING] mql_protocol\ - Extract FlashEA_Refactored_Complete_v2.zip
)
if exist "mql_grid" (
    echo   [OK] mql_grid\ ^(4 files^)
) else (
    echo   [MISSING] mql_grid\ - Extract FlashEA_Refactored_Complete_v2.zip
)
echo.
echo ========================================================================
pause
