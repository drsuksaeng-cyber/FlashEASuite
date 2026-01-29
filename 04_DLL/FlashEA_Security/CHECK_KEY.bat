@echo off
echo ===================================
echo Checking Security_Real.cpp key...
echo ===================================
echo.

REM Check for NEW key
findstr /C:"29mdr5kcSS3HuUWJEso6" Security_Real.cpp >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Security_Real.cpp has OLD KEY!
    echo.
    echo Line 22 should contain: 29mdr5kcSS3HuUWJEso6
    echo.
    echo YOU MUST:
    echo   1. DELETE Security_Real.cpp
    echo   2. RE-DOWNLOAD Security_Real.cpp from Claude
    echo   3. Check line 22 has: MIIBIjANBg...A29mdr5kc...
    echo   4. Rebuild DLL
    echo.
) else (
    echo [OK] Security_Real.cpp has NEW KEY!
    echo.
    echo Key starts with: 29mdr5kc (CORRECT)
    echo.
)

echo ===================================
echo Checking current directory...
echo ===================================
echo.
echo Current location: %CD%
echo.

if exist "FlashEA_Security.dll" (
    dir FlashEA_Security.dll | find "FlashEA_Security.dll"
) else (
    echo No FlashEA_Security.dll found here
)

echo.
pause
