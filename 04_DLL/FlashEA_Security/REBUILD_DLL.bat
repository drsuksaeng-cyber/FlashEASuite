@echo off
REM ===================================================================
REM FlashEA Security DLL - Complete Rebuild
REM After updating public key
REM ===================================================================

echo ===================================
echo FlashEA Security - Complete Rebuild
echo With NEW Public Key + REAL HWID
echo ===================================
echo.

REM Check if running in x64 Native Tools Command Prompt
where cl.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: cl.exe not found!
    echo.
    echo Please run from:
    echo "x64 Native Tools Command Prompt for VS 2019/2022"
    echo.
    pause
    exit /b 1
)

REM Set vcpkg paths
set VCPKG_ROOT=C:\vcpkg
set VCPKG_INCLUDE=%VCPKG_ROOT%\installed\x64-windows\include
set VCPKG_LIB=%VCPKG_ROOT%\installed\x64-windows\lib
set VCPKG_BIN=%VCPKG_ROOT%\installed\x64-windows\bin

REM Check vcpkg
if not exist "%VCPKG_INCLUDE%" (
    echo ERROR: vcpkg not found at %VCPKG_ROOT%
    pause
    exit /b 1
)

echo Step 1: Clean previous build...
del *.obj *.dll *.lib *.exp 2>nul
echo   Done.
echo.

echo Step 2: Compiling with NEW public key...
echo.

cl.exe /c /EHsc /O2 /MD /DNDEBUG ^
    /I"%VCPKG_INCLUDE%" ^
    Security_Real.cpp ^
    LicenseVerifier.cpp ^
    HWIDGenerator.cpp ^
    RSAVerifier.cpp

if errorlevel 1 (
    echo.
    echo ===================================
    echo COMPILATION FAILED!
    echo ===================================
    pause
    exit /b 1
)

echo.
echo Step 3: Linking DLL...
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
    echo ===================================
    echo LINKING FAILED!
    echo ===================================
    pause
    exit /b 1
)

echo.
echo ===================================
echo BUILD SUCCESSFUL!
echo With NEW Public Key
echo ===================================
echo.

dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.

echo Step 4: Copying OpenSSL DLLs...
if exist "%VCPKG_BIN%\libssl-3-x64.dll" (
    copy "%VCPKG_BIN%\libssl-3-x64.dll" . >nul
    echo   libssl-3-x64.dll copied
)
if exist "%VCPKG_BIN%\libcrypto-3-x64.dll" (
    copy "%VCPKG_BIN%\libcrypto-3-x64.dll" . >nul
    echo   libcrypto-3-x64.dll copied
)
echo.

echo ===================================
echo NEXT STEPS:
echo ===================================
echo 1. Copy these files to MT5\Libraries\:
echo    - FlashEA_Security.dll
echo    - libssl-3-x64.dll
echo    - libcrypto-3-x64.dll
echo.
echo 2. Copy License_REAL.key to:
echo    MT5\Files\License.key
echo    (rename to License.key)
echo.
echo 3. Restart MT5
echo.
echo 4. Test:
echo    - GetMyHWID.mq5 (verify HWID)
echo    - TestDLLWrapper.mq5 (should pass 5/5)
echo.
echo ===================================
echo Ready to deploy!
echo ===================================
echo.
pause
