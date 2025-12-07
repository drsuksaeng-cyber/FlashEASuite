@echo off
REM ========================================================================
REM FlashEASuite V2 - Project Cleanup & Restructuring Script
REM ========================================================================
REM Purpose: Clean up junk files, organize documentation, and rename folders
REM Date: December 6, 2025
REM ========================================================================

echo.
echo ========================================================================
echo FlashEASuite V2 - Project Cleanup Script
echo ========================================================================
echo.
echo This script will:
echo   1. Delete unused/junk files
echo   2. Organize documentation
echo   3. Rename main folders
echo.
echo WARNING: This operation cannot be undone!
echo.
pause

REM ========================================================================
REM STEP 1: DELETE UNUSED/JUNK FILES
REM ========================================================================

echo.
echo ========================================================================
echo STEP 1: Deleting unused/junk files...
echo ========================================================================

REM Delete python_fixed folder
if exist "python_fixed" (
    echo [DELETE] python_fixed/ folder...
    rmdir /s /q "python_fixed"
    echo [OK] Deleted python_fixed/
) else (
    echo [SKIP] python_fixed/ not found
)

REM Delete test files (EXCEPT test_feedback_loop.py)
echo.
echo [DELETE] Test files...
for %%f in (
    "02_ProgramB_Brain_Py\test_brain_server.py"
    "02_ProgramB_Brain_Py\test_feeder.py"
    "02_ProgramB_Brain_Py\test_policy_sender.py"
    "02_ProgramB_Brain_Py\test_port_scanner.py"
    "02_ProgramB_Brain_Py\test_trade_receiver.py"
    "02_ProgramB_Brain_Py\test_zmq_receive.py"
    "02_ProgramB_Brain_Py\simple_server.py"
    "02_ProgramB_Brain_Py\spike_simulation.py"
    "02_ProgramB_Brain_Py\SimpleSender.mq5"
    "03_ProgramC_Trader_MQL\TestNetworkingLayer.mq5"
    "03_ProgramC_Trader_MQL\TestTradeReporter.mq5"
    "03_ProgramC_Trader_MQL\files\test_brain_server.py"
    "03_ProgramC_Trader_MQL\files\TestNetworkingLayer.mq5"
    "test_receiver.py"
    "test_trade_receiver.py"
    "test_zmq_receive.py"
    "simple_server.py"
    "TestTradeReporter_fixed.mq5"
    "TestTradeReporter_Standalone.mq5"
    "FeederEA_DEFINE.mq5"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete backup files (_o1 versions)
echo.
echo [DELETE] Backup files (_o1 versions)...
for %%f in (
    "03_ProgramC_Trader_MQL\ProgramC_Trader_o1.mq5"
    "Include\MqlMsgPack_o1.mqh"
    "Include\Zmq\Zmq_o1.mqh"
    "Include\Zmq\ZmqHub_o1.mqh"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete empty placeholder files
echo.
echo [DELETE] Empty placeholder files...
for %%f in (
    "03_ProgramC_Trader_MQL\Config\Settings.mqh"
    "Include\Logic\Strategy_Standalone.mqh"
    "Include\Logic\Strategy_Trend.mqh"
    "02_ProgramB_Brain_Py\modules\ga_optimizer.py"
    "02_ProgramB_Brain_Py\modules\regime_analyzer.py"
    "Include\Zmq\czmq_placeholder.txt"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete duplicate files in root
echo.
echo [DELETE] Duplicate files in root...
for %%f in (
    "main.py"
    "PolicyManager.mqh"
    "ProgramC_Trader.mq5"
    "Strategy_Grid.mqh"
    "strategy_threading.py"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete temporary files
echo.
echo [DELETE] Temporary files...
for %%f in (
    "new chat4.txt"
    "generate_keys.py"
) do (
    if exist %%f (
        del /q %%f
        echo [OK] Deleted %%f
    )
)

REM Delete files folder (duplicates)
if exist "03_ProgramC_Trader_MQL\files" (
    echo.
    echo [DELETE] 03_ProgramC_Trader_MQL\files\ folder (duplicates)...
    rmdir /s /q "03_ProgramC_Trader_MQL\files"
    echo [OK] Deleted files\ folder
)

REM Delete Config folder (empty)
if exist "03_ProgramC_Trader_MQL\Config" (
    echo.
    echo [DELETE] 03_ProgramC_Trader_MQL\Config\ folder (empty)...
    rmdir /s /q "03_ProgramC_Trader_MQL\Config"
    echo [OK] Deleted Config\ folder
)

REM Delete .git folder
if exist ".git" (
    echo.
    echo [DELETE] .git\ folder...
    rmdir /s /q ".git"
    echo [OK] Deleted .git\ folder
)

echo.
echo [STEP 1 COMPLETE] Junk files deleted!

REM ========================================================================
REM STEP 2: ORGANIZE DOCUMENTATION
REM ========================================================================

echo.
echo ========================================================================
echo STEP 2: Organizing documentation...
echo ========================================================================

REM Create docs folder structure
echo.
echo [CREATE] docs\ folder structure...
if not exist "docs" mkdir "docs"
if not exist "docs\installation" mkdir "docs\installation"
if not exist "docs\fixes" mkdir "docs\fixes"
if not exist "docs\guides" mkdir "docs\guides"
if not exist "docs\summaries" mkdir "docs\summaries"
if not exist "docs\archive" mkdir "docs\archive"
echo [OK] Created docs\ folders

REM Move installation docs
echo.
echo [MOVE] Installation documentation...
for %%f in (
    "COMPLETE_RUN_GUIDE.md"
    "INSTALLATION_README.md"
    "02_ProgramB_Brain_Py\QUICKSTART.md"
    "02_ProgramB_Brain_Py\QUICK_START.md"
) do (
    if exist %%f (
        move /y %%f "docs\installation\" >nul 2>&1
        echo [OK] Moved %%f
    )
)

REM Move fix documentation
echo.
echo [MOVE] Fix documentation...
for %%f in (
    "FINAL_FIX_TIMESTAMP.md"
    "FIX_ACCESS_VIOLATION.md"
    "FIX_PROGRAMC_ERRORS.md"
    "FIX_SYNTAX_ERROR.md"
    "QUICK_FIX_SUMMARY.md"
) do (
    if exist %%f (
        move /y %%f "docs\fixes\" >nul 2>&1
        echo [OK] Moved %%f
    )
)

REM Move guides
echo.
echo [MOVE] Guides...
for %%f in (
    "02_ProgramB_Brain_Py\FEEDBACK_LOOP_GUIDE.md"
    "02_ProgramB_Brain_Py\TEST_TRADE_RESULT_GUIDE.md"
    "00_Common\ProtocolSpecs.md"
) do (
    if exist %%f (
        move /y %%f "docs\guides\" >nul 2>&1
        echo [OK] Moved %%f
    )
)

REM Move summaries
echo.
echo [MOVE] Summaries...
for %%f in (
    "FINAL_SOLUTION_COMPLETE.md"
    "MASTER_SUMMARY.md"
    "PACKAGE_SUMMARY.md"
    "02_ProgramB_Brain_Py\TASK1_SUMMARY.md"
    "DOWNLOAD_CHECKLIST.md"
    "QUICK_SUMMARY.md"
    "READY_TO_TEST.md"
) do (
    if exist %%f (
        move /y %%f "docs\summaries\" >nul 2>&1
        echo [OK] Moved %%f
    )
)

REM Move Trader .txt files to archive
echo.
echo [MOVE] Trader documentation to archive...
for %%f in (
    "03_ProgramC_Trader_MQL\DELIVERY_SUMMARY.txt"
    "03_ProgramC_Trader_MQL\INSTALLATION_INSTRUCTIONS.txt"
    "03_ProgramC_Trader_MQL\INTEGRATION_GUIDE.txt"
    "03_ProgramC_Trader_MQL\QUICK_FIX_FOR_YOUR_STRUCTURE.txt"
    "03_ProgramC_Trader_MQL\README.txt"
    "03_ProgramC_Trader_MQL\START_HERE.txt"
) do (
    if exist %%f (
        move /y %%f "docs\archive\" >nul 2>&1
        echo [OK] Moved %%f
    )
)

REM Move Brain README
if exist "02_ProgramB_Brain_Py\README.md" (
    move /y "02_ProgramB_Brain_Py\README.md" "docs\guides\" >nul 2>&1
    echo [OK] Moved 02_ProgramB_Brain_Py\README.md
)

REM Delete 00_Common folder if empty
if exist "00_Common" (
    rmdir "00_Common" >nul 2>&1
    if not exist "00_Common" (
        echo [OK] Deleted empty 00_Common\ folder
    )
)

echo.
echo [STEP 2 COMPLETE] Documentation organized!

REM ========================================================================
REM STEP 3: RENAME MAIN FOLDERS
REM ========================================================================

echo.
echo ========================================================================
echo STEP 3: Renaming main folders...
echo ========================================================================

REM Rename Feeder folder
if exist "01_ProgramA_Feeder_MQL" (
    if not exist "01_Feeder" (
        echo [RENAME] 01_ProgramA_Feeder_MQL -^> 01_Feeder
        ren "01_ProgramA_Feeder_MQL" "01_Feeder"
        echo [OK] Renamed to 01_Feeder
    ) else (
        echo [SKIP] 01_Feeder already exists
    )
) else (
    echo [SKIP] 01_ProgramA_Feeder_MQL not found
)

REM Rename Brain folder
if exist "02_ProgramB_Brain_Py" (
    if not exist "02_Brain" (
        echo [RENAME] 02_ProgramB_Brain_Py -^> 02_Brain
        ren "02_ProgramB_Brain_Py" "02_Brain"
        echo [OK] Renamed to 02_Brain
    ) else (
        echo [SKIP] 02_Brain already exists
    )
) else (
    echo [SKIP] 02_ProgramB_Brain_Py not found
)

REM Rename Trader folder
if exist "03_ProgramC_Trader_MQL" (
    if not exist "03_Trader" (
        echo [RENAME] 03_ProgramC_Trader_MQL -^> 03_Trader
        ren "03_ProgramC_Trader_MQL" "03_Trader"
        echo [OK] Renamed to 03_Trader
    ) else (
        echo [SKIP] 03_Trader already exists
    )
) else (
    echo [SKIP] 03_ProgramC_Trader_MQL not found
)

echo.
echo [STEP 3 COMPLETE] Folders renamed!

REM ========================================================================
REM STEP 4: CREATE MOVE LOG
REM ========================================================================

echo.
echo ========================================================================
echo STEP 4: Creating move log...
echo ========================================================================

echo FlashEASuite V2 - Cleanup Log > CLEANUP_LOG.txt
echo Date: %date% %time% >> CLEANUP_LOG.txt
echo. >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo DELETED FILES: >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo - python_fixed/ folder >> CLEANUP_LOG.txt
echo - test_*.py files (except test_feedback_loop.py) >> CLEANUP_LOG.txt
echo - *_o1.mq5 and *_o1.mqh backup files >> CLEANUP_LOG.txt
echo - Empty placeholder files >> CLEANUP_LOG.txt
echo - Duplicate files in root >> CLEANUP_LOG.txt
echo - .git/ folder >> CLEANUP_LOG.txt
echo. >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo MOVED FILES: >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo - All .md/.txt documentation to docs/ >> CLEANUP_LOG.txt
echo. >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo RENAMED FOLDERS: >> CLEANUP_LOG.txt
echo ======================================== >> CLEANUP_LOG.txt
echo - 01_ProgramA_Feeder_MQL -^> 01_Feeder >> CLEANUP_LOG.txt
echo - 02_ProgramB_Brain_Py -^> 02_Brain >> CLEANUP_LOG.txt
echo - 03_ProgramC_Trader_MQL -^> 03_Trader >> CLEANUP_LOG.txt

echo [OK] Created CLEANUP_LOG.txt

REM ========================================================================
REM COMPLETION
REM ========================================================================

echo.
echo ========================================================================
echo CLEANUP COMPLETE!
echo ========================================================================
echo.
echo Summary:
echo   - Deleted unused/junk files
echo   - Organized documentation in docs/
echo   - Renamed main folders
echo   - Created CLEANUP_LOG.txt
echo.
echo Next steps:
echo   1. Review CLEANUP_LOG.txt
echo   2. Run Phase 2: Python modularization
echo   3. Run Phase 3: MQL5 modularization
echo.
echo ========================================================================
pause
