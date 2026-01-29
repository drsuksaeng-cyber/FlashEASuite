@echo off
REM ===================================================================
REM CRITICAL: Rebuild with CORRECT Security_Real.cpp
REM ===================================================================

echo ===================================
echo REBUILD with NEW Public Key
echo ===================================
echo.

echo Step 1: Checking current Security_Real.cpp...
echo.

REM Check if we have the new key
findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Security_Real.cpp has OLD public key!
    echo.
    echo You MUST:
    echo   1. Delete Security_Real.cpp
    echo   2. Copy NEW Security_Real.cpp from download
    echo   3. Run this script again
    echo.
    pause
    exit /b 1
) else (
    echo [OK] Security_Real.cpp has NEW public key!
    echo.
)

echo Step 2: Cleaning...
del *.obj *.dll *.lib *.exp 2>nul
echo   Done.
echo.

echo Step 3: Compiling...
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
    echo.
    echo [ERROR] Compilation failed!
    pause
    exit /b 1
)

echo.
echo Step 4: Linking...
echo.

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
    echo.
    echo [ERROR] Linking failed!
    pause
    exit /b 1
)

echo.
echo ===================================
echo BUILD SUCCESSFUL!
echo ===================================
echo.

dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.

echo Step 5: Copying OpenSSL DLLs...
copy "%VCPKG_BIN%\libssl-3-x64.dll" . >nul
copy "%VCPKG_BIN%\libcrypto-3-x64.dll" . >nul
echo   Done.
echo.

echo ===================================
echo DLL Built with NEW Public Key!
echo ===================================
echo.
echo Next: Run DEPLOY_TO_MT5.bat
echo.
pause
