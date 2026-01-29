@echo off
REM Build FlashEA_Security.dll (Quick Test Version)
REM Visual Studio 2019+ Required

echo ====================================
echo FlashEA_Security.dll Build Script
echo Quick Test Version
echo ====================================
echo.

REM Check if cl.exe is available
where cl.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Visual Studio compiler not found!
    echo.
    echo Please run this from:
    echo - Visual Studio Developer Command Prompt
    echo OR
    echo - Developer PowerShell for VS 2019/2022
    echo.
    pause
    exit /b 1
)

echo Compiler found: OK
echo.

REM Clean old files
echo Cleaning old files...
if exist Security.obj del Security.obj
if exist FlashEA_Security.dll del FlashEA_Security.dll
if exist FlashEA_Security.lib del FlashEA_Security.lib
if exist FlashEA_Security.exp del FlashEA_Security.exp
echo.

REM Compile
echo Compiling Security.cpp...
cl.exe /c /EHsc /O2 /MD /DNDEBUG Security.cpp
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Compilation failed!
    pause
    exit /b 1
)
echo Compilation: OK
echo.

REM Link
echo Linking DLL...
link.exe /DLL /OUT:FlashEA_Security.dll Security.obj kernel32.lib user32.lib
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Linking failed!
    pause
    exit /b 1
)
echo Linking: OK
echo.

REM Check output
if exist FlashEA_Security.dll (
    echo ====================================
    echo BUILD SUCCESSFUL!
    echo ====================================
    echo.
    echo Output: FlashEA_Security.dll
    echo Size: 
    dir FlashEA_Security.dll | find "FlashEA_Security.dll"
    echo.
    echo Next steps:
    echo 1. Copy FlashEA_Security.dll to:
    echo    MT5\Libraries\FlashEA_Security.dll
    echo.
    echo 2. Test with TestDLLWrapper.mq5
    echo.
) else (
    echo ERROR: DLL not created!
    pause
    exit /b 1
)

pause
