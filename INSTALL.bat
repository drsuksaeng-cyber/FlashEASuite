@echo off
REM ====================================================================
REM DAY 1 INSTALLATION SCRIPT - Windows
REM FlashEASuite V2.1 - Option A
REM ====================================================================

echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║     DAY 1 INSTALLATION - AUTOMATED                       ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

REM Check if we're in the right directory
if not exist "Include" (
    echo ❌ ERROR: Not in FlashEASuite_V2 directory!
    echo.
    echo Current directory: %CD%
    echo Expected: FlashEASuite_V2\
    echo.
    echo Please run this script from FlashEASuite_V2 directory!
    pause
    exit /b 1
)

echo ✅ Found FlashEASuite_V2 directory
echo.

REM ====================================================================
REM STEP 1: Create Directories
REM ====================================================================
echo [STEP 1/4] Creating directories...

if not exist "Include\Risk" (
    mkdir "Include\Risk"
    echo   ✅ Created Include\Risk\
) else (
    echo   ✓ Include\Risk\ already exists
)

if not exist "Scripts\Tests" (
    mkdir "Scripts\Tests"
    echo   ✅ Created Scripts\Tests\
) else (
    echo   ✓ Scripts\Tests\ already exists
)

if not exist "02_Brain\core\risk_management" (
    mkdir "02_Brain\core\risk_management"
    echo   ✅ Created 02_Brain\core\risk_management\
) else (
    echo   ✓ 02_Brain\core\risk_management\ already exists
)

echo.

REM ====================================================================
REM STEP 2: Copy MQL5 Files
REM ====================================================================
echo [STEP 2/4] Installing MQL5 files...

set SOURCE_DIR=%~dp0

copy "%SOURCE_DIR%PositionSizingManager.mqh" "Include\Risk\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ PositionSizingManager.mqh → Include\Risk\
) else (
    echo   ❌ Failed to copy PositionSizingManager.mqh
)

copy "%SOURCE_DIR%DailyLossLimit.mqh" "Include\Risk\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ DailyLossLimit.mqh → Include\Risk\
) else (
    echo   ❌ Failed to copy DailyLossLimit.mqh
)

copy "%SOURCE_DIR%RiskGuardian.mqh" "Include\Risk\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ RiskGuardian.mqh → Include\Risk\ [REPLACED]
) else (
    echo   ❌ Failed to copy RiskGuardian.mqh
)

echo.

REM ====================================================================
REM STEP 3: Copy Test Scripts
REM ====================================================================
echo [STEP 3/4] Installing test scripts...

copy "%SOURCE_DIR%test_position_sizing.mq5" "Scripts\Tests\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ test_position_sizing.mq5 → Scripts\Tests\
) else (
    echo   ❌ Failed to copy test_position_sizing.mq5
)

copy "%SOURCE_DIR%test_daily_loss_limit.mq5" "Scripts\Tests\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ test_daily_loss_limit.mq5 → Scripts\Tests\
) else (
    echo   ❌ Failed to copy test_daily_loss_limit.mq5
)

copy "%SOURCE_DIR%test_integration_day1.mq5" "Scripts\Tests\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ test_integration_day1.mq5 → Scripts\Tests\
) else (
    echo   ❌ Failed to copy test_integration_day1.mq5
)

echo.

REM ====================================================================
REM STEP 4: Copy Python Files
REM ====================================================================
echo [STEP 4/4] Installing Python files...

copy "%SOURCE_DIR%__init__.py" "02_Brain\core\risk_management\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ __init__.py → 02_Brain\core\risk_management\
) else (
    echo   ❌ Failed to copy __init__.py
)

copy "%SOURCE_DIR%position_sizing.py" "02_Brain\core\risk_management\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ position_sizing.py → 02_Brain\core\risk_management\
) else (
    echo   ❌ Failed to copy position_sizing.py
)

copy "%SOURCE_DIR%daily_loss_limit.py" "02_Brain\core\risk_management\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   ✅ daily_loss_limit.py → 02_Brain\core\risk_management\
) else (
    echo   ❌ Failed to copy daily_loss_limit.py
)

echo.

REM ====================================================================
REM VERIFICATION
REM ====================================================================
echo ╔══════════════════════════════════════════════════════════╗
echo ║                  VERIFICATION                            ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

set ERRORS=0

echo Checking MQL5 files...
if exist "Include\Risk\PositionSizingManager.mqh" (echo   ✅ PositionSizingManager.mqh) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "Include\Risk\DailyLossLimit.mqh" (echo   ✅ DailyLossLimit.mqh) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "Include\Risk\RiskGuardian.mqh" (echo   ✅ RiskGuardian.mqh) else (echo   ❌ Missing & set /a ERRORS+=1)

echo.
echo Checking test scripts...
if exist "Scripts\Tests\test_position_sizing.mq5" (echo   ✅ test_position_sizing.mq5) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "Scripts\Tests\test_daily_loss_limit.mq5" (echo   ✅ test_daily_loss_limit.mq5) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "Scripts\Tests\test_integration_day1.mq5" (echo   ✅ test_integration_day1.mq5) else (echo   ❌ Missing & set /a ERRORS+=1)

echo.
echo Checking Python files...
if exist "02_Brain\core\risk_management\__init__.py" (echo   ✅ __init__.py) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "02_Brain\core\risk_management\position_sizing.py" (echo   ✅ position_sizing.py) else (echo   ❌ Missing & set /a ERRORS+=1)
if exist "02_Brain\core\risk_management\daily_loss_limit.py" (echo   ✅ daily_loss_limit.py) else (echo   ❌ Missing & set /a ERRORS+=1)

echo.
echo ══════════════════════════════════════════════════════════

if %ERRORS% EQU 0 (
    echo.
    echo ✅✅✅ INSTALLATION SUCCESSFUL! ✅✅✅
    echo.
    echo All 9 files installed correctly!
    echo.
    echo Next steps:
    echo   1. Open MetaEditor
    echo   2. Compile MQL5 files (Press F7)
    echo   3. Run tests (see RUN_TESTS.bat)
    echo.
) else (
    echo.
    echo ❌ INSTALLATION FAILED!
    echo.
    echo %ERRORS% file(s) missing!
    echo Please check:
    echo   1. All 9 source files in same directory as this script
    echo   2. File permissions
    echo   3. Disk space
    echo.
)

pause
