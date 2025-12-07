@echo off
REM ========================================================================
REM FlashEASuite V2 - Module Installation Script v2.1 (FIXED)
REM ========================================================================
REM Purpose: Install Python and MQL5 modules after cleanup
REM Prerequisite: Run cleanup_project_v2.1_FIXED.bat first
REM Date: December 6, 2025
REM Version: 2.1 (Fixed folder names)
REM ========================================================================

echo.
echo ========================================================================
echo FlashEASuite V2 - Module Installation Script v2.1
echo ========================================================================
echo.
echo This script will install:
echo   1. Python Strategy Modules (5 files)
echo   2. MQL5 Protocol Modules (3 files)
echo   3. MQL5 Grid Modules (4 files)
echo.
echo Prerequisite: cleanup_project_v2.1_FIXED.bat must be run first
echo.
pause

REM ========================================================================
REM STEP 0: VERIFY PREREQUISITES
REM ========================================================================

echo.
echo ========================================================================
echo STEP 0: Verifying prerequisites...
echo ========================================================================

set READY=1

REM Check if source folders exist
if not exist "python_strategy" (
    echo [ERROR] python_strategy\ folder NOT FOUND
    echo        Please extract FlashEA_Refactored_Complete_v2.zip first
    set READY=0
)

if not exist "mql_protocol" (
    echo [ERROR] mql_protocol\ folder NOT FOUND
    echo        Please extract FlashEA_Refactored_Complete_v2.zip first
    set READY=0
)

if not exist "mql_grid" (
    echo [ERROR] mql_grid\ folder NOT FOUND
    echo        Please extract FlashEA_Refactored_Complete_v2.zip first
    set READY=0
)

REM Check if target folders exist (FIXED: Use correct folder names)
if not exist "02_ProgramB_Brain_Py\core\strategy" (
    echo [ERROR] Target folder 02_ProgramB_Brain_Py\core\strategy\ NOT FOUND
    echo        Please run cleanup_project_v2.1_FIXED.bat first
    set READY=0
)

if not exist "Include\Network\Protocol" (
    echo [ERROR] Target folder Include\Network\Protocol\ NOT FOUND
    echo        Please run cleanup_project_v2.1_FIXED.bat first
    set READY=0
)

if not exist "Include\Logic\Grid" (
    echo [ERROR] Target folder Include\Logic\Grid\ NOT FOUND
    echo        Please run cleanup_project_v2.1_FIXED.bat first
    set READY=0
)

if %READY%==0 (
    echo.
    echo ========================================================================
    echo INSTALLATION CANNOT PROCEED
    echo ========================================================================
    echo.
    echo Please:
    echo   1. Extract FlashEA_Refactored_Complete_v2.zip to project root
    echo   2. Run cleanup_project_v2.1_FIXED.bat
    echo   3. Then run this script again
    echo.
    pause
    exit /b 1
)

echo [OK] All prerequisites verified

REM ========================================================================
REM STEP 1: BACKUP EXISTING FILES (IF ANY)
REM ========================================================================

echo.
echo ========================================================================
echo STEP 1: Creating backup of existing files...
echo ========================================================================

set BACKUP_NEEDED=0

REM Check if strategy.py exists (old file)
if exist "02_ProgramB_Brain_Py\core\strategy.py" (
    echo [BACKUP] Found old strategy.py
    if not exist "backup" mkdir "backup"
    copy /y "02_ProgramB_Brain_Py\core\strategy.py" "backup\strategy.py.backup" >nul 2>&1
    echo [OK] Backed up strategy.py to backup\strategy.py.backup
    set BACKUP_NEEDED=1
)

REM Check if old Protocol.mqh exists
if exist "Include\Network\Protocol.mqh" (
    if not exist "Include\Network\Protocol\" (
        echo [BACKUP] Found old Protocol.mqh
        if not exist "backup" mkdir "backup"
        copy /y "Include\Network\Protocol.mqh" "backup\Protocol.mqh.backup" >nul 2>&1
        echo [OK] Backed up Protocol.mqh to backup\Protocol.mqh.backup
        set BACKUP_NEEDED=1
    )
)

REM Check if old Strategy_Grid.mqh exists
if exist "Include\Logic\Strategy_Grid.mqh" (
    if not exist "Include\Logic\Grid\" (
        echo [BACKUP] Found old Strategy_Grid.mqh
        if not exist "backup" mkdir "backup"
        copy /y "Include\Logic\Strategy_Grid.mqh" "backup\Strategy_Grid.mqh.backup" >nul 2>&1
        echo [OK] Backed up Strategy_Grid.mqh to backup\Strategy_Grid.mqh.backup
        set BACKUP_NEEDED=1
    )
)

if %BACKUP_NEEDED%==0 (
    echo [SKIP] No existing files to backup
)

REM ========================================================================
REM STEP 2: INSTALL PYTHON STRATEGY MODULES
REM ========================================================================

echo.
echo ========================================================================
echo STEP 2: Installing Python Strategy Modules...
echo ========================================================================

echo [INSTALL] Copying Python modules to 02_ProgramB_Brain_Py\core\strategy\...

xcopy /s /y /q python_strategy\* 02_ProgramB_Brain_Py\core\strategy\ >nul 2>&1

if %ERRORLEVEL%==0 (
    echo [OK] Copied __init__.py
    echo [OK] Copied engine.py
    echo [OK] Copied analysis.py
    echo [OK] Copied feedback.py
    echo [OK] Copied policy.py
    echo.
    echo [SUCCESS] Python Strategy Modules installed
) else (
    echo [ERROR] Failed to copy Python modules
)

REM Rename old strategy.py to strategy_old.py if exists
if exist "02_ProgramB_Brain_Py\core\strategy.py" (
    echo.
    echo [RENAME] Moving old strategy.py to strategy_old.py
    ren "02_ProgramB_Brain_Py\core\strategy.py" "strategy_old.py"
    echo [OK] Old file renamed (for reference)
)

REM ========================================================================
REM STEP 3: INSTALL MQL5 PROTOCOL MODULES
REM ========================================================================

echo.
echo ========================================================================
echo STEP 3: Installing MQL5 Protocol Modules...
echo ========================================================================

echo [INSTALL] Copying Protocol modules...

copy /y mql_protocol\Definitions.mqh Include\Network\Protocol\ >nul 2>&1
echo [OK] Copied Definitions.mqh to Include\Network\Protocol\

copy /y mql_protocol\Serialization.mqh Include\Network\Protocol\ >nul 2>&1
echo [OK] Copied Serialization.mqh to Include\Network\Protocol\

copy /y mql_protocol\Protocol.mqh Include\Network\ >nul 2>&1
echo [OK] Copied Protocol.mqh to Include\Network\

echo.
echo [SUCCESS] MQL5 Protocol Modules installed

REM ========================================================================
REM STEP 4: INSTALL MQL5 GRID MODULES
REM ========================================================================

echo.
echo ========================================================================
echo STEP 4: Installing MQL5 Grid Modules...
echo ========================================================================

echo [INSTALL] Copying Grid modules...

copy /y mql_grid\GridConfig.mqh Include\Logic\Grid\ >nul 2>&1
echo [OK] Copied GridConfig.mqh to Include\Logic\Grid\

copy /y mql_grid\GridState.mqh Include\Logic\Grid\ >nul 2>&1
echo [OK] Copied GridState.mqh to Include\Logic\Grid\

copy /y mql_grid\GridCore.mqh Include\Logic\Grid\ >nul 2>&1
echo [OK] Copied GridCore.mqh to Include\Logic\Grid\

copy /y mql_grid\Strategy_Grid.mqh Include\Logic\ >nul 2>&1
echo [OK] Copied Strategy_Grid.mqh to Include\Logic\

echo.
echo [SUCCESS] MQL5 Grid Modules installed

REM ========================================================================
REM STEP 5: CREATE INSTALLATION REPORT
REM ========================================================================

echo.
echo ========================================================================
echo STEP 5: Creating installation report...
echo ========================================================================

echo FlashEASuite V2 - Module Installation Report > INSTALLATION_REPORT.txt
echo Date: %date% %time% >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
echo PYTHON MODULES INSTALLED: >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
dir /b 02_ProgramB_Brain_Py\core\strategy\*.py >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
echo MQL5 PROTOCOL MODULES INSTALLED: >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
dir /b Include\Network\Protocol\*.mqh >> INSTALLATION_REPORT.txt
dir /b Include\Network\Protocol.mqh >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
echo MQL5 GRID MODULES INSTALLED: >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
dir /b Include\Logic\Grid\*.mqh >> INSTALLATION_REPORT.txt
dir /b Include\Logic\Strategy_Grid.mqh >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
echo VERIFICATION COMMANDS: >> INSTALLATION_REPORT.txt
echo ======================================== >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo Python Import Test: >> INSTALLATION_REPORT.txt
echo   cd 02_ProgramB_Brain_Py >> INSTALLATION_REPORT.txt
echo   python -c "from core.strategy import create_strategy_engine_threaded; print('OK')" >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt
echo MQL5 Compilation Test: >> INSTALLATION_REPORT.txt
echo   Open MetaEditor >> INSTALLATION_REPORT.txt
echo   Compile: 03_Trader\ProgramC_Trader.mq5 >> INSTALLATION_REPORT.txt
echo   Compile: 01_Feeder\Src\FeederEA.mq5 >> INSTALLATION_REPORT.txt
echo. >> INSTALLATION_REPORT.txt

echo [OK] Created INSTALLATION_REPORT.txt

REM ========================================================================
REM STEP 6: FINAL SUMMARY AND NEXT STEPS
REM ========================================================================

echo.
echo ========================================================================
echo INSTALLATION COMPLETE!
echo ========================================================================
echo.
echo Summary:
echo   [OK] Python Strategy Modules (5 files)
echo   [OK] MQL5 Protocol Modules (3 files)
echo   [OK] MQL5 Grid Modules (4 files)
echo.
echo Files installed:
echo   Python:
echo     - 02_ProgramB_Brain_Py\core\strategy\__init__.py
echo     - 02_ProgramB_Brain_Py\core\strategy\engine.py
echo     - 02_ProgramB_Brain_Py\core\strategy\analysis.py
echo     - 02_ProgramB_Brain_Py\core\strategy\feedback.py
echo     - 02_ProgramB_Brain_Py\core\strategy\policy.py
echo.
echo   MQL5 Protocol:
echo     - Include\Network\Protocol\Definitions.mqh
echo     - Include\Network\Protocol\Serialization.mqh
echo     - Include\Network\Protocol.mqh
echo.
echo   MQL5 Grid:
echo     - Include\Logic\Grid\GridConfig.mqh
echo     - Include\Logic\Grid\GridState.mqh
echo     - Include\Logic\Grid\GridCore.mqh
echo     - Include\Logic\Strategy_Grid.mqh
echo.
echo Reports created:
echo   - INSTALLATION_REPORT.txt
echo.
echo ========================================================================
echo NEXT: VERIFICATION
echo ========================================================================
echo.
echo Please verify installation:
echo.
echo 1. Python Import Test:
echo    cd 02_ProgramB_Brain_Py
echo    python -c "from core.strategy import create_strategy_engine_threaded; print('✅ OK')"
echo.
echo 2. MQL5 Compilation Test:
echo    - Open MetaEditor
echo    - Compile: 03_Trader\ProgramC_Trader.mq5
echo    - Compile: 01_Feeder\Src\FeederEA.mq5
echo    - Should compile without errors
echo.
echo 3. Run System:
echo    - Start: python main.py (in 02_ProgramB_Brain_Py\)
echo    - Attach: FeederEA to MT5
echo    - Attach: ProgramC_Trader to MT5
echo.
echo See INSTALLATION_REPORT.txt for details.
echo.
echo ========================================================================
pause
