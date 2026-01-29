@echo off
REM Simple Diagnostic Check

set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052
set REPORT=DIAGNOSTIC_REPORT.txt

echo ================================================= > %REPORT%
echo FlashEA Security - Diagnostic Report >> %REPORT%
echo ================================================= >> %REPORT%
echo. >> %REPORT%

echo [1] DLL Source Directory >> %REPORT%
echo Current: %CD% >> %REPORT%
echo. >> %REPORT%
if exist "FlashEA_Security.dll" (
    dir FlashEA_Security.dll >> %REPORT%
) else (
    echo ERROR: FlashEA_Security.dll NOT FOUND! >> %REPORT%
)
echo. >> %REPORT%

echo [2] MT5 Libraries >> %REPORT%
echo Path: %MT5_PATH%\MQL5\Libraries\ >> %REPORT%
echo. >> %REPORT%
if exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
    dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" >> %REPORT%
) else (
    echo ERROR: FlashEA_Security.dll NOT in MT5! >> %REPORT%
)
if exist "%MT5_PATH%\MQL5\Libraries\libssl-3-x64.dll" (
    echo OK: libssl-3-x64.dll found >> %REPORT%
) else (
    echo ERROR: libssl-3-x64.dll missing! >> %REPORT%
)
if exist "%MT5_PATH%\MQL5\Libraries\libcrypto-3-x64.dll" (
    echo OK: libcrypto-3-x64.dll found >> %REPORT%
) else (
    echo ERROR: libcrypto-3-x64.dll missing! >> %REPORT%
)
echo. >> %REPORT%

echo [3] License File >> %REPORT%
echo Path: %MT5_PATH%\MQL5\Files\ >> %REPORT%
echo. >> %REPORT%
if exist "%MT5_PATH%\MQL5\Files\License.key" (
    dir "%MT5_PATH%\MQL5\Files\License.key" >> %REPORT%
    echo. >> %REPORT%
    echo First few lines: >> %REPORT%
    type "%MT5_PATH%\MQL5\Files\License.key" | more +0 >> %REPORT%
) else (
    echo ERROR: License.key NOT FOUND! >> %REPORT%
)
echo. >> %REPORT%

echo [4] Debug Log >> %REPORT%
if exist "%MT5_PATH%\MQL5\Libraries\dll_debug.log" (
    type "%MT5_PATH%\MQL5\Libraries\dll_debug.log" >> %REPORT%
) else (
    echo No debug log found >> %REPORT%
)
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo End of Report >> %REPORT%
echo ================================================= >> %REPORT%

echo.
echo Report created: %REPORT%
echo Opening...
echo.
notepad %REPORT%
pause
