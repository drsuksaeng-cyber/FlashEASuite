@echo off
REM ===================================================================
REM STEP-BY-STEP FIX with Verification
REM ===================================================================

echo ===================================
echo FlashEA Security - Complete Fix
echo ===================================
echo.

REM Step 0: Show current location
echo [Step 0] Current directory:
echo %CD%
echo.
pause

REM Step 1: Check Security_Real.cpp
echo.
echo [Step 1] Checking Security_Real.cpp...
echo.

if not exist "Security_Real.cpp" (
    echo [ERROR] Security_Real.cpp NOT FOUND!
    echo.
    echo Please ensure you are in: 04_DLL\FlashEA_Security\
    echo.
    pause
    exit /b 1
)

findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Security_Real.cpp has OLD PUBLIC KEY!
    echo.
    echo What you see in Security_Real.cpp line 22-23:
    type Security_Real.cpp | find "MIIBIj" | more
    echo.
    echo This should start with: MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA29mdr5kc...
    echo                                                                      ^^^^^^^^
    echo                                                                      (29mdr5kc)
    echo.
    echo ACTION REQUIRED:
    echo   1. Press any key to exit
    echo   2. Delete this Security_Real.cpp
    echo   3. Download Security_Real.cpp again from Claude
    echo   4. Copy to this folder
    echo   5. Run this script again
    echo.
    pause
    exit /b 1
)

echo [OK] Security_Real.cpp has NEW public key!
echo.
pause

REM Step 2: Clean
echo.
echo [Step 2] Cleaning old files...
del *.obj *.dll *.lib *.exp 2>nul
echo [OK] Cleaned
echo.
pause

REM Step 3: Build
echo.
echo [Step 3] Building DLL...
echo.

set VCPKG_ROOT=C:\vcpkg
set VCPKG_INCLUDE=%VCPKG_ROOT%\installed\x64-windows\include
set VCPKG_LIB=%VCPKG_ROOT%\installed\x64-windows\lib
set VCPKG_BIN=%VCPKG_ROOT%\installed\x64-windows\bin

cl.exe /c /EHsc /O2 /MD /DNDEBUG ^
    /I"%VCPKG_INCLUDE%" ^
    Security_Real.cpp ^
    LicenseVerifier.cpp ^
    HWIDGenerator.cpp ^
    RSAVerifier.cpp

if errorlevel 1 (
    echo [ERROR] Compilation failed!
    pause
    exit /b 1
)

link.exe /DLL /MACHINE:X64 ^
    /LIBPATH:"%VCPKG_LIB%" ^
    /OUT:FlashEA_Security.dll ^
    Security_Real.obj ^
    LicenseVerifier.obj ^
    HWIDGenerator.obj ^
    RSAVerifier.obj ^
    libssl.lib ^
    libcrypto.lib ^
    ws2_32.lib ^
    crypt32.lib ^
    advapi32.lib ^
    wbemuuid.lib ^
    ole32.lib ^
    oleaut32.lib

if errorlevel 1 (
    echo [ERROR] Linking failed!
    pause
    exit /b 1
)

copy "%VCPKG_BIN%\libssl-3-x64.dll" . >nul
copy "%VCPKG_BIN%\libcrypto-3-x64.dll" . >nul

echo.
echo [OK] DLL Built!
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.
pause

REM Step 4: Deploy
echo.
echo [Step 4] Deploying to MT5...
echo.

set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

echo Closing MT5 if running...
taskkill /F /IM terminal64.exe 2>nul
taskkill /F /IM terminal.exe 2>nul
timeout /t 2 >nul

echo.
echo Copying DLLs...
copy "FlashEA_Security.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libssl-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libcrypto-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y

echo.
echo [OK] Files deployed!
echo.
dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" | find "FlashEA_Security.dll"
echo.
pause

REM Step 5: Verify
echo.
echo [Step 5] Verification...
echo.
echo Source DLL:
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.
echo MT5 DLL:
dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" | find "FlashEA_Security.dll"
echo.
echo License:
dir "%MT5_PATH%\MQL5\Files\License.key" | find "License.key"
echo.

echo ===================================
echo COMPLETE!
echo ===================================
echo.
echo Next steps:
echo   1. Start MT5
echo   2. Run TestPublicKey.mq5
echo   3. Should see: Result: 1 (SUCCESS!)
echo.
echo If still error -3:
echo   - Security_Real.cpp still has old key
echo   - Re-download and try again
echo.
pause
