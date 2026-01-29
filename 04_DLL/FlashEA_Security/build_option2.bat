@echo off
REM ===================================================================
REM FlashEA Security DLL Builder - Option 2 (Real Implementation)
REM Requires: vcpkg with OpenSSL and RapidJSON installed
REM ===================================================================

echo ===================================
echo FlashEA Security DLL Builder
echo Option 2: Real Implementation
echo With OpenSSL + RapidJSON
echo ===================================
echo.

REM Check if running in x64 Native Tools Command Prompt
where cl.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: cl.exe not found!
    echo.
    echo Please run this script from:
    echo "x64 Native Tools Command Prompt for VS 2019/2022"
    echo.
    pause
    exit /b 1
)

REM Clean previous build
echo Cleaning previous build...
del *.obj *.dll *.lib *.exp 2>nul
echo Done.
echo.

REM Set vcpkg paths
set VCPKG_ROOT=C:\vcpkg
set VCPKG_INCLUDE=%VCPKG_ROOT%\installed\x64-windows\include
set VCPKG_LIB=%VCPKG_ROOT%\installed\x64-windows\lib
set VCPKG_BIN=%VCPKG_ROOT%\installed\x64-windows\bin

REM Check if vcpkg installed
if not exist "%VCPKG_INCLUDE%" (
    echo ERROR: vcpkg not found at %VCPKG_ROOT%
    echo.
    echo Please install:
    echo   cd C:\
    echo   git clone https://github.com/Microsoft/vcpkg.git
    echo   cd vcpkg
    echo   bootstrap-vcpkg.bat
    echo   vcpkg integrate install
    echo   vcpkg install openssl:x64-windows
    echo   vcpkg install rapidjson:x64-windows
    echo.
    pause
    exit /b 1
)

echo Compiling...
echo.

REM Compile all source files
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
echo Linking...
echo.

REM Link DLL with OpenSSL + Registry (advapi32.lib added!)
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
echo BUILD SUCCESSFUL! (64-BIT)
echo With OpenSSL + RapidJSON + Registry
echo ===================================
echo.

REM Show file size
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.

REM Copy required OpenSSL DLLs
echo Copying OpenSSL DLLs...
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
echo Files to copy to MT5:
echo ===================================
echo 1. FlashEA_Security.dll
echo 2. libssl-3-x64.dll
echo 3. libcrypto-3-x64.dll
echo.
echo Copy to: MT5\Libraries\
echo.
echo ===================================
echo Ready to test!
echo ===================================
echo.
pause
