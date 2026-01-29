@echo off
REM ===================================================================
REM Auto-Deploy to MT5
REM After building DLL
REM ===================================================================

echo ===================================
echo Auto-Deploy to MT5
echo ===================================
echo.

REM SET YOUR MT5 PATH HERE:
set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

REM Check if MT5 path exists
if not exist "%MT5_PATH%" (
    echo ERROR: MT5 path not found!
    echo Please update MT5_PATH in this script
    echo.
    pause
    exit /b 1
)

echo MT5 Path: %MT5_PATH%
echo.

REM Check if DLLs exist
if not exist "FlashEA_Security.dll" (
    echo ERROR: FlashEA_Security.dll not found!
    echo Please build DLL first using REBUILD_DLL.bat
    echo.
    pause
    exit /b 1
)

echo Step 1: Copying DLLs to MT5\Libraries\...
copy "FlashEA_Security.dll" "%MT5_PATH%\MQL5\Libraries\" /Y >nul
if errorlevel 1 (
    echo   ERROR: Failed to copy FlashEA_Security.dll
    pause
    exit /b 1
)
echo   ✓ FlashEA_Security.dll

copy "libssl-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y >nul
if errorlevel 1 (
    echo   ERROR: Failed to copy libssl-3-x64.dll
    pause
    exit /b 1
)
echo   ✓ libssl-3-x64.dll

copy "libcrypto-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y >nul
if errorlevel 1 (
    echo   ERROR: Failed to copy libcrypto-3-x64.dll
    pause
    exit /b 1
)
echo   ✓ libcrypto-3-x64.dll

echo.
echo Step 2: Checking License_REAL.key...
if exist "License_REAL.key" (
    echo   Found License_REAL.key
    echo   Copying to MT5\Files\License.key...
    
    REM Create Files directory if not exists
    if not exist "%MT5_PATH%\MQL5\Files" mkdir "%MT5_PATH%\MQL5\Files"
    
    copy "License_REAL.key" "%MT5_PATH%\MQL5\Files\License.key" /Y >nul
    if errorlevel 1 (
        echo   ERROR: Failed to copy license
        pause
        exit /b 1
    )
    echo   ✓ License.key copied
) else (
    echo   WARNING: License_REAL.key not found in current directory
    echo   Please copy manually to: %MT5_PATH%\MQL5\Files\License.key
)

echo.
echo ===================================
echo DEPLOYMENT COMPLETE!
echo ===================================
echo.
echo Files deployed to:
echo   %MT5_PATH%\MQL5\Libraries\
echo   %MT5_PATH%\MQL5\Files\
echo.
echo NEXT STEPS:
echo   1. Restart MT5
echo   2. Run GetMyHWID.mq5 to verify HWID
echo   3. Run TestDLLWrapper.mq5 (expect 5/5 PASSED)
echo.
echo ===================================
echo Ready to test!
echo ===================================
echo.
pause
