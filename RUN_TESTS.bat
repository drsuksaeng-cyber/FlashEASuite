@echo off
REM ====================================================================
REM DAY 1 TEST RUNNER - Windows
REM FlashEASuite V2.1 - Option A
REM ====================================================================

echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║     DAY 1 TESTS - AUTOMATED RUNNER                       ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

REM Check if we're in the right directory
if not exist "Scripts\Tests" (
    echo ❌ ERROR: Scripts\Tests directory not found!
    echo.
    echo Please run INSTALL.bat first!
    pause
    exit /b 1
)

echo This script will guide you through testing.
echo.
echo ══════════════════════════════════════════════════════════
echo IMPORTANT INSTRUCTIONS:
echo ══════════════════════════════════════════════════════════
echo.
echo MQL5 Tests (Manual in MT5):
echo   1. Open MT5 Terminal
echo   2. Open any chart (e.g., EURUSD M1)
echo   3. Drag test scripts to chart one by one:
echo.
echo      Test 1: Scripts\Tests\test_position_sizing.mq5
echo              Expected: 10/10 tests pass
echo.
echo      Test 2: Scripts\Tests\test_daily_loss_limit.mq5
echo              Expected: 7/7 tests pass
echo.
echo      Test 3: Scripts\Tests\test_integration_day1.mq5
echo              Expected: 6/6 tests pass ⭐
echo.
echo   4. Check Experts tab for results
echo.
echo ══════════════════════════════════════════════════════════
echo.

set /p RUN_PYTHON="Run Python tests now? (Y/N): "

if /i "%RUN_PYTHON%"=="Y" goto :run_python
if /i "%RUN_PYTHON%"=="YES" goto :run_python

echo.
echo ✅ Manual testing mode
echo.
echo Follow the instructions above for MQL5 tests.
echo.
echo For Python tests, run:
echo   cd 02_Brain
echo   python core/risk_management/position_sizing.py
echo   python core/risk_management/daily_loss_limit.py
echo.
pause
exit /b 0

:run_python
echo.
echo ══════════════════════════════════════════════════════════
echo PYTHON TESTS
echo ══════════════════════════════════════════════════════════
echo.

REM Check if Python exists
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Python not found!
    echo Please install Python first.
    pause
    exit /b 1
)

echo Python found: 
python --version
echo.

REM Change to Brain directory
cd 02_Brain

echo [TEST 1/3] Testing Position Sizing import...
python -c "from core.risk_management import PositionSizingManager; print('✅ Import OK')" 2>nul
if %ERRORLEVEL% EQU 0 (
    echo   ✅ PASS - Position Sizing imports correctly
) else (
    echo   ❌ FAIL - Import error
)
echo.

echo [TEST 2/3] Testing Daily Loss Limit import...
python -c "from core.risk_management import DailyLossLimit; print('✅ Import OK')" 2>nul
if %ERRORLEVEL% EQU 0 (
    echo   ✅ PASS - Daily Loss Limit imports correctly
) else (
    echo   ❌ FAIL - Import error
)
echo.

echo [TEST 3/3] Running Position Sizing tests...
python core/risk_management/position_sizing.py
echo.

echo [TEST 4/3] Running Daily Loss Limit tests...
python core/risk_management/daily_loss_limit.py
echo.

cd ..

echo ══════════════════════════════════════════════════════════
echo PYTHON TESTS COMPLETE
echo ══════════════════════════════════════════════════════════
echo.
echo Don't forget to run MQL5 tests in MT5!
echo (See instructions at the top)
echo.

pause
