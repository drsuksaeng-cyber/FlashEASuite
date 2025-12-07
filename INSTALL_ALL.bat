@echo off
REM ========================================
REM FlashEASuite V2 - Auto Installation Script
REM ========================================
echo.
echo ========================================
echo FlashEASuite V2 - Auto Installation
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

echo [OK] Base directory found
echo %BASE_DIR%
echo.

REM Check if files.zip exists
if not exist "files.zip" (
    echo ERROR: files.zip not found!
    echo Please place files.zip in the current directory.
    pause
    exit /b 1
)

echo [OK] files.zip found
echo.

REM Create temp extraction folder
set TEMP_DIR=%BASE_DIR%\temp_extract
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

echo Step 1: Extracting files.zip...
echo.

REM Extract using PowerShell (built-in Windows)
powershell -command "Expand-Archive -Path '%BASE_DIR%\files.zip' -DestinationPath '%TEMP_DIR%' -Force"

if errorlevel 1 (
    echo ERROR: Failed to extract files.zip
    pause
    exit /b 1
)

echo [OK] Extraction complete
echo.

REM ========================================
REM Step 2: Copy MQL5 Files
REM ========================================
echo Step 2: Installing MQL5 files...
echo.

REM Create directories if they don't exist
if not exist "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src" mkdir "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src"
if not exist "%BASE_DIR%\03_ProgramC_Trader_MQL" mkdir "%BASE_DIR%\03_ProgramC_Trader_MQL"

REM Go up to MQL5 directory for Include files
set MQL5_DIR=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5
if not exist "%MQL5_DIR%\Include\Logic" mkdir "%MQL5_DIR%\Include\Logic"

REM Copy FeederEA.mq5
echo   - Copying FeederEA_DEFINE.mq5 to Feeder/Src/FeederEA.mq5...
copy /Y "%TEMP_DIR%\FeederEA_DEFINE.mq5" "%BASE_DIR%\01_ProgramA_Feeder_MQL\Src\FeederEA.mq5" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

REM Copy ProgramC_Trader.mq5
echo   - Copying ProgramC_Trader.mq5 to Trader...
copy /Y "%TEMP_DIR%\ProgramC_Trader.mq5" "%BASE_DIR%\03_ProgramC_Trader_MQL\ProgramC_Trader.mq5" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

REM Copy Strategy_Grid.mqh
echo   - Copying Strategy_Grid.mqh to Include/Logic...
copy /Y "%TEMP_DIR%\Strategy_Grid.mqh" "%MQL5_DIR%\Include\Logic\Strategy_Grid.mqh" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

REM Copy PolicyManager.mqh
echo   - Copying PolicyManager.mqh to Include/Logic...
copy /Y "%TEMP_DIR%\PolicyManager.mqh" "%MQL5_DIR%\Include\Logic\PolicyManager.mqh" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

echo.

REM ========================================
REM Step 3: Copy Python Files
REM ========================================
echo Step 3: Installing Python files...
echo.

REM Create directories if they don't exist
if not exist "%BASE_DIR%\02_ProgramB_Brain_Py" mkdir "%BASE_DIR%\02_ProgramB_Brain_Py"
if not exist "%BASE_DIR%\02_ProgramB_Brain_Py\core" mkdir "%BASE_DIR%\02_ProgramB_Brain_Py\core"

REM Copy main.py
echo   - Copying main.py to Brain...
copy /Y "%TEMP_DIR%\main.py" "%BASE_DIR%\02_ProgramB_Brain_Py\main.py" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

REM Copy strategy_threading.py
echo   - Copying strategy_threading.py to Brain/core/strategy.py...
copy /Y "%TEMP_DIR%\strategy_threading.py" "%BASE_DIR%\02_ProgramB_Brain_Py\core\strategy.py" >nul
if errorlevel 1 (
    echo     [FAILED]
) else (
    echo     [OK]
)

echo.

REM ========================================
REM Step 4: Cleanup
REM ========================================
echo Step 4: Cleaning up...
rmdir /s /q "%TEMP_DIR%"
echo [OK] Temp files removed
echo.

REM ========================================
REM Step 5: Verification
REM ========================================
echo ========================================
echo Installation Complete!
echo ========================================
echo.
echo Installed files:
echo   MQL5:
echo     - FeederEA.mq5           (Feeder/Src)
echo     - ProgramC_Trader.mq5    (Trader)
echo     - Strategy_Grid.mqh      (Include/Logic)
echo     - PolicyManager.mqh      (Include/Logic)
echo.
echo   Python:
echo     - main.py                (Brain)
echo     - strategy.py            (Brain/core)
echo.
echo ========================================
echo Next Steps:
echo ========================================
echo 1. Open MetaEditor
echo 2. Compile FeederEA.mq5 (F7)
echo    Expected: 0 errors
echo 3. Compile ProgramC_Trader.mq5 (F7)
echo    Expected: 0 errors
echo.
echo 4. Test Python:
echo    cd 02_ProgramB_Brain_Py
echo    python -c "from core.strategy import StrategyEngineThreaded; print('OK')"
echo.
echo 5. Run system:
echo    - Attach FeederEA to XAUUSD chart
echo    - Run: python main.py
echo    - Attach ProgramC_Trader to XAUUSD chart
echo.
echo ========================================
echo.
pause
