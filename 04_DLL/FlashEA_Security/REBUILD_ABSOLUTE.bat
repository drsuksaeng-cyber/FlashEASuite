@echo off
REM ===================================================================
REM ABSOLUTE CLEAN REBUILD
REM Guarantee fresh compilation
REM ===================================================================

echo ===================================
echo ABSOLUTE CLEAN REBUILD
echo ===================================
echo.

set VCPKG_ROOT=C:\vcpkg
set VCPKG_INCLUDE=%VCPKG_ROOT%\installed\x64-windows\include
set VCPKG_LIB=%VCPKG_ROOT%\installed\x64-windows\lib
set VCPKG_BIN=%VCPKG_ROOT%\installed\x64-windows\bin

REM Step 1: Verify source
echo [Step 1] Verifying Security_Real.cpp...
if not exist "Security_Real.cpp" (
    echo ERROR: Security_Real.cpp not found!
    pause
    exit /b 1
)

findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >nul 2>&1
if errorlevel 1 (
    echo.
    echo ============================================
    echo CRITICAL ERROR: Security_Real.cpp has OLD KEY!
    echo ============================================
    echo.
    echo Current key in line 22:
    type Security_Real.cpp | more +21 | head -1
    echo.
    echo Should be: MIIBIjANBg...A29mdr5kcSS3HuUWJEso6...
    echo                         ^^^^^^^^
    echo                         (29mdr5kc)
    echo.
    echo ACTION:
    echo   1. Exit this script
    echo   2. Open Security_Real.cpp in Notepad
    echo   3. Go to line 21-22
    echo   4. Replace the ENTIRE public key block with:
    echo.
    echo const char* g_PublicKeyPEM = R"(-----BEGIN PUBLIC KEY-----
    echo MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA29mdr5kcSS3HuUWJEso6
    echo 3nxeHpnxN72oS6oFeWQGzQEcOFNxyCMa9JMPlEKmhcc411VjhaNUO7s3p9zEyXxD
    echo i4uqdJ6PyM7SHGd/Xo0PP3wjJL6LVR+8pOh5l14xdPF/ZTgKBEDvpYw89GjBqJYi
    echo xo7+LzYxAMlmEohjT+Q9b0+soO2z96rNfYPezHQ4sVZ4OBeQG7FUKJ5H0sOOOOrO
    echo nv7l12pMOXEGxaxQmbkj7COeaaL9fDi6pddYIUqHqCi4RW0acJeY1fY6SxDrVp3E
    echo rV3RGkexcA9ZsGS7H7/VFnyb8DtSuS49g+y00iQ+9RZ2l+abYl31gmbTmNQg9PFq
    echo bwIDAQAB
    echo -----END PUBLIC KEY-----)";
    echo.
    echo   5. Save file
    echo   6. Run this script again
    echo.
    pause
    exit /b 1
)

echo [OK] Security_Real.cpp has NEW key
echo.

REM Step 2: Nuclear clean
echo [Step 2] NUCLEAR CLEAN - Deleting everything...
del /Q Security_Real.obj 2>nul
del /Q LicenseVerifier.obj 2>nul
del /Q HWIDGenerator.obj 2>nul
del /Q RSAVerifier.obj 2>nul
del /Q FlashEA_Security.dll 2>nul
del /Q FlashEA_Security.lib 2>nul
del /Q FlashEA_Security.exp 2>nul
del /Q vc*.pdb 2>nul

echo [OK] All old files deleted
echo.
pause

REM Step 3: Compile Security_Real.cpp FIRST
echo [Step 3] Compiling Security_Real.cpp (WATCH FOR ERRORS)...
echo.

cl.exe /c /EHsc /O2 /MD /DNDEBUG /I"%VCPKG_INCLUDE%" Security_Real.cpp

if errorlevel 1 (
    echo.
    echo ERROR: Security_Real.cpp compilation failed!
    pause
    exit /b 1
)

if not exist "Security_Real.obj" (
    echo.
    echo ERROR: Security_Real.obj was not created!
    pause
    exit /b 1
)

echo.
echo [OK] Security_Real.obj created
dir Security_Real.obj | find "Security_Real.obj"
echo.
pause

REM Step 4: Compile other files
echo [Step 4] Compiling other files...
echo.

cl.exe /c /EHsc /O2 /MD /DNDEBUG /I"%VCPKG_INCLUDE%" LicenseVerifier.cpp HWIDGenerator.cpp RSAVerifier.cpp

if errorlevel 1 (
    echo ERROR: Other files compilation failed!
    pause
    exit /b 1
)

echo [OK] All files compiled
echo.
pause

REM Step 5: Link
echo [Step 5] Linking DLL...
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
    echo ERROR: Linking failed!
    pause
    exit /b 1
)

if not exist "FlashEA_Security.dll" (
    echo ERROR: DLL was not created!
    pause
    exit /b 1
)

echo.
echo [OK] DLL created
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.

copy "%VCPKG_BIN%\libssl-3-x64.dll" . >nul
copy "%VCPKG_BIN%\libcrypto-3-x64.dll" . >nul

pause

REM Step 6: Deploy
echo [Step 6] Deploying to MT5...
set MT5_PATH=C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052

echo Killing MT5...
taskkill /F /IM terminal64.exe 2>nul
taskkill /F /IM terminal.exe 2>nul
timeout /t 2 >nul

echo Deleting old DLL...
del "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" 2>nul

echo Copying new DLL...
copy "FlashEA_Security.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libssl-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y
copy "libcrypto-3-x64.dll" "%MT5_PATH%\MQL5\Libraries\" /Y

echo.
echo [OK] Deployed
echo.

REM Step 7: Final verification
echo [Step 7] Final Verification...
echo.
echo Source DLL:
dir FlashEA_Security.dll | find "FlashEA_Security.dll"
echo.
echo MT5 DLL:
dir "%MT5_PATH%\MQL5\Libraries\FlashEA_Security.dll" | find "FlashEA_Security.dll"
echo.

echo ===================================
echo REBUILD COMPLETE!
echo ===================================
echo.
echo This DLL was compiled with:
echo   - NEW public key (29mdr5kc...)
echo   - Fresh Security_Real.obj
echo   - No cached files
echo.
echo Next:
echo   1. Start MT5
echo   2. Run TestPublicKey.mq5
echo   3. MUST see: Result: 1 (SUCCESS!)
echo.
echo If still error -3:
echo   - Something is very wrong
echo   - Send DEBUG_DEEP.bat output to Claude
echo.
pause
