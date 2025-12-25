@echo off
REM ================================================================
REM FlashEASuite V2 - Restructure Wrapper
REM This script calls the actual RESTRUCTURE.bat in Restructure_Package
REM ================================================================

echo.
echo Starting FlashEASuite V2 Restructure...
echo.

REM Check if Restructure_Package exists
if not exist "Restructure_Package" (
    echo ERROR: Restructure_Package folder not found!
    echo.
    echo Please make sure you have extracted FlashEASuite_V2_Restructure.zip
    echo in the FlashEASuite_V2 directory.
    echo.
    pause
    exit /b 1
)

REM Check if RESTRUCTURE.bat exists
if not exist "Restructure_Package\RESTRUCTURE.bat" (
    echo ERROR: RESTRUCTURE.bat not found in Restructure_Package!
    echo.
    echo Please re-extract FlashEASuite_V2_Restructure.zip
    echo.
    pause
    exit /b 1
)

REM Run the actual restructure script
call "Restructure_Package\RESTRUCTURE.bat"

echo.
echo Restructure complete!
echo.
pause
