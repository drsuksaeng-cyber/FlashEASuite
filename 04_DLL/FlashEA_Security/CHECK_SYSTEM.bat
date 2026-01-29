@echo off
REM ===================================================================
REM Diagnostic Report Generator
REM Check all files and configurations
REM ===================================================================

setlocal enabledelayedexpansion

echo ===================================
echo FlashEA Security - Diagnostic Report
echo ===================================
echo.

set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052
set OUTPUT_FILE=DIAGNOSTIC_REPORT.txt

echo Generating diagnostic report...
echo Please wait...
echo.

REM Start report
echo ================================================================= > %OUTPUT_FILE%
echo FlashEA Security - Diagnostic Report >> %OUTPUT_FILE%
echo Generated: %DATE% %TIME% >> %OUTPUT_FILE%
echo ================================================================= >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%

REM Check DLL source
echo [1/5] Checking DLL source files... >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo Source Directory: %CD% >> %OUTPUT_FILE%
if exist "FlashEA_Security.dll" (
    dir FlashEA_Security.dll | find "FlashEA_Security.dll" >> %OUTPUT_FILE%
    certutil -hashfile FlashEA_Security.dll MD5 | find /v "CertUtil" >> %OUTPUT_FILE%
) else (
    echo   [ERROR] FlashEA_Security.dll NOT FOUND in source! >> %OUTPUT_FILE%
)
if exist "License_REAL.key" (
    dir License_REAL.key | find "License_REAL.key" >> %OUTPUT_FILE%
) else (
    echo   [WARNING] License_REAL.key NOT FOUND in source! >> %OUTPUT_FILE%
)
echo. >> %OUTPUT_FILE%

REM Check MT5 Libraries
echo [2/5] Checking MT5 Libraries... >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo Libraries Path: %MT5_PATH%\MQL5\Libraries\ >> %OUTPUT_FILE%
if exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
    dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" | find "FlashEA_Security.dll" >> %OUTPUT_FILE%
    certutil -hashfile "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" MD5 | find /v "CertUtil" >> %OUTPUT_FILE%
) else (
    echo   [ERROR] FlashEA_Security.dll NOT FOUND in MT5! >> %OUTPUT_FILE%
)
if exist "%MT5_PATH%\MQL5\Libraries\libssl-3-x64.dll" (
    echo   [OK] libssl-3-x64.dll found >> %OUTPUT_FILE%
) else (
    echo   [ERROR] libssl-3-x64.dll NOT FOUND! >> %OUTPUT_FILE%
)
if exist "%MT5_PATH%\MQL5\Libraries\libcrypto-3-x64.dll" (
    echo   [OK] libcrypto-3-x64.dll found >> %OUTPUT_FILE%
) else (
    echo   [ERROR] libcrypto-3-x64.dll NOT FOUND! >> %OUTPUT_FILE%
)
echo. >> %OUTPUT_FILE%

REM Check License file
echo [3/5] Checking License file... >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo Files Path: %MT5_PATH%\MQL5\Files\ >> %OUTPUT_FILE%
if exist "%MT5_PATH%\MQL5\Files\License.key" (
    dir "%MT5_PATH%\MQL5\Files\License.key" | find "License.key" >> %OUTPUT_FILE%
    echo   First 3 lines of License.key: >> %OUTPUT_FILE%
    powershell -Command "Get-Content '%MT5_PATH%\MQL5\Files\License.key' | Select-Object -First 3" >> %OUTPUT_FILE%
    echo   License ID check: >> %OUTPUT_FILE%
    findstr /C:"license_id" "%MT5_PATH%\MQL5\Files\License.key" >> %OUTPUT_FILE%
    findstr /C:"hwid" "%MT5_PATH%\MQL5\Files\License.key" >> %OUTPUT_FILE%
) else (
    echo   [ERROR] License.key NOT FOUND! >> %OUTPUT_FILE%
)
echo. >> %OUTPUT_FILE%

REM Check DLL hash comparison
echo [4/5] Comparing DLL hashes... >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
if exist "FlashEA_Security.dll" (
    if exist "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" (
        echo Source DLL hash: >> %OUTPUT_FILE%
        certutil -hashfile FlashEA_Security.dll MD5 | find /v "CertUtil" >> %OUTPUT_FILE%
        echo MT5 DLL hash: >> %OUTPUT_FILE%
        certutil -hashfile "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" MD5 | find /v "CertUtil" >> %OUTPUT_FILE%
        
        REM Simple hash comparison
        for /f "skip=1 tokens=*" %%a in ('certutil -hashfile FlashEA_Security.dll MD5') do (
            set SOURCE_HASH=%%a
            goto :break1
        )
        :break1
        for /f "skip=1 tokens=*" %%a in ('certutil -hashfile "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" MD5') do (
            set MT5_HASH=%%a
            goto :break2
        )
        :break2
        
        if "!SOURCE_HASH!"=="!MT5_HASH!" (
            echo   [OK] Hashes MATCH - DLL is up to date >> %OUTPUT_FILE%
        ) else (
            echo   [ERROR] Hashes DIFFER - DLL not deployed correctly! >> %OUTPUT_FILE%
        )
    )
)
echo. >> %OUTPUT_FILE%

REM Check debug log if exists
echo [5/5] Checking debug logs... >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
if exist "%MT5_PATH%\MQL5\Libraries\dll_debug.log" (
    echo Last 20 lines of dll_debug.log: >> %OUTPUT_FILE%
    powershell -Command "Get-Content '%MT5_PATH%\MQL5\Libraries\dll_debug.log' | Select-Object -Last 20" >> %OUTPUT_FILE%
) else (
    echo   [INFO] dll_debug.log not found (may not be generated yet) >> %OUTPUT_FILE%
)
echo. >> %OUTPUT_FILE%

REM Summary
echo ================================================================= >> %OUTPUT_FILE%
echo End of Diagnostic Report >> %OUTPUT_FILE%
echo ================================================================= >> %OUTPUT_FILE%

echo.
echo ===================================
echo Report generated successfully!
echo ===================================
echo.
echo Report saved to: %OUTPUT_FILE%
echo.
echo Please open %OUTPUT_FILE% and copy ALL contents
echo Then paste to Claude for analysis
echo.
echo ===================================
echo.

REM Open the report
notepad %OUTPUT_FILE%

pause
