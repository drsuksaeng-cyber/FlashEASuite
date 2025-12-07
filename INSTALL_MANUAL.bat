@echo off
REM ========================================
REM FlashEASuite V2 - Manual Files Installation
REM (For individual files, not zipped)
REM ========================================
echo.
echo ========================================
echo FlashEASuite V2 - Installation
echo (Individual Files Version)
echo ========================================
echo.

REM Set base directory
set BASE_DIR=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5\Experts\FlashEASuite_V2

REM Check if we're in the correct directory
cd /d "%BASE_DIR%"
if errorlevel 1 (
    echo ERROR: Cannot access base directory
    echo %BASE_DIR%
    pause
    exit /b 1
)

echo [OK] Base directory: %BASE_DIR%
echo.

REM Check if required files exist
echo Checking files...
set MISSING=0

if not exist "FeederEA_DEFINE.mq5" (
    echo   [MISSING] FeederEA_DEFINE.mq5
    set MISSING=1
) else (
    echo   [OK] FeederEA_DEFINE.mq5
)

if not exist "ProgramC_Trader.mq5" (
    echo   [MISSING] ProgramC_Trader.mq5
    set MISSING=1
) else (
    echo   [OK] ProgramC_Trader.mq5
)

if not exist "Strategy_Grid.mqh" (
    echo   [MISSING] Strategy_Grid.mqh
    set MISSING=1
) else (
    echo   [OK] Strategy_Grid.mqh
)

if not exist "PolicyManager.mqh" (
    echo   [MISSING] PolicyManager.mqh
    set MISSING=1
) else (
    echo   [OK] PolicyManager.mqh
)

if not exist "main.py" (
    echo   [MISSING] main.py
    set MISSING=1
) else (
    echo   [OK] main.py
)

if not exist "strategy_threading.py" (
    echo   [MISSING] strategy_threading.py
    set MISSING=1
) else (
    echo   [OK] strategy_threading.py
)

echo.

if %MISSING%==1 (
    echo ERROR: Some files are missing!
    echo Please download all 6 files and place them in:
    echo %BASE_DIR%
    pause
    exit /b 1
)

echo All files found!
echo.

REM Ask for confirmation
echo Ready to install files to:
echo   - 01_ProgramA_Feeder_MQL\Src\
echo   - 02_ProgramB_Brain_Py\
echo   - 03_ProgramC_Trader_MQL\
echo   - MQL5\Include\Logic\
echo.
echo This will OVERWRITE existing files.
echo.
set /p CONFIRM=Continue? (Y/N): 
if /i not "%CONFIRM%"=="Y" (
    echo Installation cancelled.
    pause
    exit /b 0
)

echo.

REM ========================================
REM Step 1: Create directories
REM ========================================
echo Step 1: Creating directories...
echo.

if not exist "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src" (
    mkdir "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src"
    echo   [CREATED] 01_ProgramA_Feeder_MQL\Src
)

if not exist "%BASE_DIR%\02_ProgramB_Brain_Py\core" (
    mkdir "%BASE_DIR%\02_ProgramB_Brain_Py\core"
    echo   [CREATED] 02_ProgramB_Brain_Py\core
)

if not exist "%BASE_DIR%\03_ProgramC_Trader_MQL" (
    mkdir "%BASE_DIR%\03_ProgramC_Trader_MQL"
    echo   [CREATED] 03_ProgramC_Trader_MQL
)

set MQL5_DIR=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5
if not exist "%MQL5_DIR%\Include\Logic" (
    mkdir "%MQL5_DIR%\Include\Logic"
    echo   [CREATED] Include\Logic
)

echo [OK] All directories ready
echo.

REM ========================================
REM Step 2: Copy files
REM ========================================
echo Step 2: Copying files...
echo.

echo   MQL5 Files:

echo     - FeederEA.mq5...
copy /Y "%BASE_DIR%\FeederEA_DEFINE.mq5" "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src\FeederEA.mq5" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo     - ProgramC_Trader.mq5...
copy /Y "%BASE_DIR%\ProgramC_Trader.mq5" "%BASE_DIR%\03_ProgramC_Trader_MQL\ProgramC_Trader.mq5" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo     - Strategy_Grid.mqh...
copy /Y "%BASE_DIR%\Strategy_Grid.mqh" "%MQL5_DIR%\Include\Logic\Strategy_Grid.mqh" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo     - PolicyManager.mqh...
copy /Y "%BASE_DIR%\PolicyManager.mqh" "%MQL5_DIR%\Include\Logic\PolicyManager.mqh" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo.
echo   Python Files:

echo     - main.py...
copy /Y "%BASE_DIR%\main.py" "%BASE_DIR%\02_ProgramB_Brain_Py\main.py" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo     - strategy.py...
copy /Y "%BASE_DIR%\strategy_threading.py" "%BASE_DIR%\02_ProgramB_Brain_Py\core\strategy.py" >nul
if errorlevel 1 (echo       [FAILED]) else (echo       [OK])

echo.

REM ========================================
REM Step 3: Create __init__.py if missing
REM ========================================
if not exist "%BASE_DIR%\02_ProgramB_Brain_Py\core\__init__.py" (
    echo. > "%BASE_DIR%\02_ProgramB_Brain_Py\core\__init__.py"
    echo [OK] Created core\__init__.py
)

REM ========================================
REM Complete
REM ========================================
echo.
echo ========================================
echo Installation Complete!
echo ========================================
echo.
echo File locations:
echo   [Feeder]  %BASE_DIR%\01_ProgramA_Feeder_MQL\Src\FeederEA.mq5
echo   [Trader]  %BASE_DIR%\03_ProgramC_Trader_MQL\ProgramC_Trader.mq5
echo   [Grid]    %MQL5_DIR%\Include\Logic\Strategy_Grid.mqh
echo   [Policy]  %MQL5_DIR%\Include\Logic\PolicyManager.mqh
echo   [Brain]   %BASE_DIR%\02_ProgramB_Brain_Py\main.py
echo   [Core]    %BASE_DIR%\02_ProgramB_Brain_Py\core\strategy.py
echo.
echo ========================================
echo Next Steps:
echo ========================================
echo.
echo 1. Compile MQL5 files:
echo    - Open MetaEditor
echo    - Open FeederEA.mq5 and press F7
echo    - Open ProgramC_Trader.mq5 and press F7
echo    - Expected: 0 errors for both
echo.
echo 2. Test Python:
echo    cd "%BASE_DIR%\02_ProgramB_Brain_Py"
echo    python -c "from core.strategy import StrategyEngineThreaded; print('OK')"
echo.
echo 3. Run system:
echo    a. MT5: Attach FeederEA to XAUUSD chart
echo    b. Terminal: python main.py
echo    c. MT5: Attach ProgramC_Trader to XAUUSD chart
echo.
echo ========================================
echo.
pause
