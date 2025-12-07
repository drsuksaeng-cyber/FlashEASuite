@echo off
REM ========================================
REM Create files.zip for Installation
REM ========================================
echo.
echo ========================================
echo FlashEASuite V2 - Create Installation ZIP
echo ========================================
echo.

REM Set base directory
set BASE_DIR=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5\Experts\FlashEASuite_V2

cd /d "%BASE_DIR%"
if errorlevel 1 (
    echo ERROR: Cannot access base directory
    pause
    exit /b 1
)

echo Current directory: %BASE_DIR%
echo.

REM Check if files exist
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
    echo Please download all 6 files first.
    pause
    exit /b 1
)

echo All files found!
echo.

REM Delete old ZIP if exists
if exist "files.zip" (
    echo Removing old files.zip...
    del /f "files.zip"
)

echo Creating files.zip...
echo.

REM Create ZIP using PowerShell
powershell -command "Compress-Archive -Path 'FeederEA_DEFINE.mq5','ProgramC_Trader.mq5','Strategy_Grid.mqh','PolicyManager.mqh','main.py','strategy_threading.py' -DestinationPath 'files.zip' -Force"

if errorlevel 1 (
    echo ERROR: Failed to create ZIP file
    pause
    exit /b 1
)

echo.
echo ========================================
echo files.zip Created Successfully!
echo ========================================
echo.
echo Location: %BASE_DIR%\files.zip
echo.
echo Contents:
echo   1. FeederEA_DEFINE.mq5
echo   2. ProgramC_Trader.mq5
echo   3. Strategy_Grid.mqh
echo   4. PolicyManager.mqh
echo   5. main.py
echo   6. strategy_threading.py
echo.
echo You can now use INSTALL_ALL.bat to install from this ZIP.
echo.
pause
