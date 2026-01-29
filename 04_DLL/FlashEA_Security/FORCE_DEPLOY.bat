@echo off
REM ===================================================================
REM FORCE DEPLOY - Kill MT5 and Deploy Fresh DLL
REM ===================================================================

echo ===================================
echo FORCE DEPLOY to MT5
echo ===================================
echo.

set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

REM Step 1: Check source DLL
echo [Step 1] Checking source DLL...
if not exist "FlashEA_Security.dll" (
    echo [ERROR] FlashEA_Security.dll not found in current directory!
    echo Current: %CD%
    pause
    exit /b 1
)

dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.
pause

REM Step 2: Kill MT5 completely
echo.
echo [Step 2] Closing MT5...
taskkill /F /IM terminal64.exe 2>nul
taskkill /F /IM terminal.exe 2>nul
echo Waiting 3 seconds...
timeout /t 3 >nul
echo.

REM Step 3: Delete old DLL from MT5
echo [Step 3] Deleting old DLL from MT5...
del "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" 2>nul
if exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
    echo [WARNING] Could not delete old DLL - file may be locked
    echo Please manually delete it and run this script again
    pause
    exit /b 1
)
echo [OK] Old DLL deleted
echo.

REM Step 4: Copy new DLL
echo [Step 4] Copying NEW DLL to MT5...
copy "FlashEA_Security.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libssl-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libcrypto-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y

if not exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
    echo [ERROR] Copy failed!
    pause
    exit /b 1
)
echo [OK] Files copied
echo.

REM Step 5: Verify
echo [Step 5] Verification...
echo.
echo Source DLL (what we built):
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.
echo MT5 DLL (what MT5 will use):
dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" | find "FlashEA_Security.dll"
echo.

REM Compare timestamps
for /f "tokens=1,2" %%a in ('dir /tc FlashEA_Security.dll ^| find "FlashEA_Security.dll"') do set SOURCE_DATE=%%a %%b
for /f "tokens=1,2" %%a in ('dir /tc "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" ^| find "FlashEA_Security.dll"') do set MT5_DATE=%%a %%b

echo Source timestamp: %SOURCE_DATE%
echo MT5 timestamp:    %MT5_DATE%
echo.

if "%SOURCE_DATE%"=="%MT5_DATE%" (
    echo [OK] Timestamps MATCH!
) else (
    echo [WARNING] Timestamps differ - but should be OK
)

echo.
echo ===================================
echo DEPLOYMENT COMPLETE!
echo ===================================
echo.
echo Next steps:
echo   1. Start MT5
echo   2. Run TestPublicKey.mq5
echo   3. Should see: Result: 1 (SUCCESS!)
echo.
echo If still error -3, then:
echo   - Try restarting Windows
echo   - Check antivirus/Windows Defender
echo.
pause
