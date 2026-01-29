@echo off
REM ===================================================================
REM Simple Debug Report (Windows Compatible)
REM ===================================================================

set REPORT=DEBUG_REPORT.txt
set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

echo Creating debug report...

echo ================================================= > %REPORT%
echo DEEP DEBUG REPORT >> %REPORT%
echo ================================================= >> %REPORT%
echo. >> %REPORT%

echo [1] Current Directory >> %REPORT%
echo %CD% >> %REPORT%
echo. >> %REPORT%

echo [2] Key Check in Security_Real.cpp >> %REPORT%
echo Searching for NEW key (29mdr5kc): >> %REPORT%
findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >> %REPORT% 2>&1
if errorlevel 1 (
    echo NEW KEY NOT FOUND >> %REPORT%
    echo Searching for OLD key: >> %REPORT%
    findstr /C:"sSzcqGxMIL+zANJC" Security_Real.cpp >> %REPORT% 2>&1
)
echo. >> %REPORT%

echo [3] Lines 20-30 of Security_Real.cpp >> %REPORT%
powershell -Command "Get-Content Security_Real.cpp | Select-Object -Skip 19 | Select-Object -First 11" >> %REPORT% 2>&1
echo. >> %REPORT%

echo [4] Source DLL >> %REPORT%
if exist "FlashEA_Security.dll" (
    dir FlashEA_Security.dll >> %REPORT%
) else (
    echo FlashEA_Security.dll NOT FOUND in source >> %REPORT%
)
echo. >> %REPORT%

echo [5] MT5 DLL >> %REPORT%
if exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
    dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" >> %REPORT%
) else (
    echo FlashEA_Security.dll NOT FOUND in MT5 >> %REPORT%
)
echo. >> %REPORT%

echo [6] OpenSSL DLLs >> %REPORT%
dir "%MT5_PATH%\MQL5\Libraries\lib*.dll" >> %REPORT% 2>&1
echo. >> %REPORT%

echo [7] License File >> %REPORT%
dir "%MT5_PATH%\MQL5\Files\License.key" >> %REPORT% 2>&1
echo. >> %REPORT%

echo [8] Debug Log >> %REPORT%
if exist "%MT5_PATH%\MQL5\Libraries\dll_debug.log" (
    type "%MT5_PATH%\MQL5\Libraries\dll_debug.log" >> %REPORT%
) else (
    echo No debug log found >> %REPORT%
)
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo END OF REPORT >> %REPORT%
echo ================================================= >> %REPORT%

echo.
echo Report created: %REPORT%
echo Opening...
notepad %REPORT%

echo.
echo Copy ALL contents and send to Claude
echo.
pause
