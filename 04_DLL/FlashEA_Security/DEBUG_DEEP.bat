@echo off
REM ===================================================================
REM Deep Debug - Find the Real Problem
REM ===================================================================

echo ===================================
echo DEEP DEBUG REPORT
echo ===================================
echo.

set REPORT=DEBUG_DEEP.txt
set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

echo Creating detailed report... > %REPORT%
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [1] Security_Real.cpp Content Check >> %REPORT%
echo ================================================= >> %REPORT%
echo Line 20-25 of Security_Real.cpp: >> %REPORT%
type Security_Real.cpp | more +19 | findstr /N "." | more +1 | head -6 >> %REPORT%
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [2] All Files in Current Directory >> %REPORT%
echo ================================================= >> %REPORT%
echo Current: %CD% >> %REPORT%
dir *.cpp *.obj *.dll *.lib >> %REPORT%
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [3] MT5 Libraries Directory >> %REPORT%
echo ================================================= >> %REPORT%
dir "%MT5_PATH%\MQL5\Libraries\FlashEA*.dll" >> %REPORT%
dir "%MT5_PATH%\MQL5\Libraries\lib*.dll" >> %REPORT%
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [4] License File >> %REPORT%
echo ================================================= >> %REPORT%
dir "%MT5_PATH%\MQL5\Files\License.key" >> %REPORT%
echo. >> %REPORT%
echo First 5 lines: >> %REPORT%
type "%MT5_PATH%\MQL5\Files\License.key" | more +0 | head -5 >> %REPORT%
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [5] Debug Log (if exists) >> %REPORT%
echo ================================================= >> %REPORT%
if exist "%MT5_PATH%\MQL5\Libraries\dll_debug.log" (
    type "%MT5_PATH%\MQL5\Libraries\dll_debug.log" >> %REPORT%
) else (
    echo No debug log found >> %REPORT%
)
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo [6] Key Search in Source >> %REPORT%
echo ================================================= >> %REPORT%
echo Searching for key patterns in Security_Real.cpp: >> %REPORT%
findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >> %REPORT% 2>&1
if errorlevel 1 (
    echo NEW KEY NOT FOUND - Has OLD key! >> %REPORT%
    findstr /C:"sSzcqGxMIL+zANJC" Security_Real.cpp >> %REPORT% 2>&1
    if errorlevel 1 (
        echo No OLD key pattern either - UNKNOWN KEY! >> %REPORT%
    ) else (
        echo OLD KEY FOUND! >> %REPORT%
    )
) else (
    echo NEW KEY FOUND - Source is correct >> %REPORT%
)
echo. >> %REPORT%

echo ================================================= >> %REPORT%
echo END OF DEBUG REPORT >> %REPORT%
echo ================================================= >> %REPORT%

echo.
echo Report created: %REPORT%
echo.
echo Opening report...
notepad %REPORT%

echo.
echo Please copy ALL contents from %REPORT%
echo and send to Claude for analysis
echo.
pause
