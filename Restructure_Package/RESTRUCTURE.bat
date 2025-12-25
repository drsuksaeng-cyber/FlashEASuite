@echo off
REM ================================================================
REM FlashEASuite V2 - Project Restructure Script
REM Version: 2.1
REM Date: December 24, 2025
REM ================================================================

echo.
echo ================================================================
echo   FlashEASuite V2 - Project Restructure
echo   Version 2.1 - Clean Structure
echo ================================================================
echo.

REM Check if running in correct directory
if not exist "Include" (
    echo ERROR: Please run this script from FlashEASuite_V2 root directory!
    echo Current directory does not contain Include folder.
    echo.
    pause
    exit /b 1
)

echo [1/7] Creating Tester directory...
if not exist "Tester" mkdir Tester
echo     - Tester\ created

echo.
echo [2/7] Moving test files to Tester...

REM Move test files from root to Tester
if exist "test_position_sizing.mq5" (
    move /Y "test_position_sizing.mq5" "Tester\" >nul 2>&1
    echo     - Moved test_position_sizing.mq5
)
if exist "test_daily_loss_limit.mq5" (
    move /Y "test_daily_loss_limit.mq5" "Tester\" >nul 2>&1
    echo     - Moved test_daily_loss_limit.mq5
)
if exist "test_integration_day1.mq5" (
    move /Y "test_integration_day1.mq5" "Tester\" >nul 2>&1
    echo     - Moved test_integration_day1.mq5
)

REM Move compiled test files
if exist "test_position_sizing.ex5" move /Y "test_position_sizing.ex5" "Tester\" >nul 2>&1
if exist "test_daily_loss_limit.ex5" move /Y "test_daily_loss_limit.ex5" "Tester\" >nul 2>&1
if exist "test_integration_day1.ex5" move /Y "test_integration_day1.ex5" "Tester\" >nul 2>&1

echo.
echo [3/7] Copying updated Day 1 files...

REM Copy updated files from restructure package
if exist "Restructure_Package\Include\Risk\PositionSizingManager.mqh" (
    copy /Y "Restructure_Package\Include\Risk\*.mqh" "Include\Risk\" >nul 2>&1
    echo     - Updated Risk modules in Include\Risk\
)

if exist "Restructure_Package\Tester\test_position_sizing.mq5" (
    copy /Y "Restructure_Package\Tester\*.mq5" "Tester\" >nul 2>&1
    echo     - Updated test files in Tester\
)

if exist "Restructure_Package\02_Brain\core\risk_management\" (
    if not exist "02_Brain\core\risk_management" mkdir "02_Brain\core\risk_management"
    copy /Y "Restructure_Package\02_Brain\core\risk_management\*.*" "02_Brain\core\risk_management\" >nul 2>&1
    echo     - Updated Python risk management modules
)

echo.
echo [4/7] Cleaning up ZIP archives...

REM Delete all .zip files
del /Q /F "*.zip" >nul 2>&1
echo     - Deleted .zip files in root

echo.
echo [5/7] Cleaning up duplicate batch files...

REM Keep only essential batch files
if exist "cleanup_project_v2.bat" del /Q /F "cleanup_project_v2.bat" >nul 2>&1
if exist "cleanup_project_v2.1_FIXED.bat" del /Q /F "cleanup_project_v2.1_FIXED.bat" >nul 2>&1
if exist "cleanup_project_v3.bat" del /Q /F "cleanup_project_v3.bat" >nul 2>&1
if exist "install_modules_v2.1_FIXED.bat" del /Q /F "install_modules_v2.1_FIXED.bat" >nul 2>&1
if exist "install_modules_v3.bat" del /Q /F "install_modules_v3.bat" >nul 2>&1
if exist "INSTALL_ALL.bat" del /Q /F "INSTALL_ALL.bat" >nul 2>&1
if exist "INSTALL_MANUAL.bat" del /Q /F "INSTALL_MANUAL.bat" >nul 2>&1
echo     - Deleted duplicate .bat files

echo.
echo [6/7] Copying documentation...

REM Copy new documentation
if exist "Restructure_Package\docs\" (
    xcopy /Y /E /I "Restructure_Package\docs\*" "docs\" >nul 2>&1
    echo     - Updated documentation in docs\
)

if exist "Restructure_Package\README.md" (
    copy /Y "Restructure_Package\README.md" "." >nul 2>&1
    echo     - Updated README.md
)

if exist "Restructure_Package\CHANGELOG.md" (
    copy /Y "Restructure_Package\CHANGELOG.md" "." >nul 2>&1
    echo     - Created CHANGELOG.md
)

if exist "Restructure_Package\PROJECT_STRUCTURE.md" (
    copy /Y "Restructure_Package\PROJECT_STRUCTURE.md" "." >nul 2>&1
    echo     - Created PROJECT_STRUCTURE.md
)

if exist "Restructure_Package\.gitignore" (
    copy /Y "Restructure_Package\.gitignore" "." >nul 2>&1
    echo     - Created .gitignore
)

if exist "Restructure_Package\Tester\README.md" (
    copy /Y "Restructure_Package\Tester\README.md" "Tester\" >nul 2>&1
    echo     - Created Tester\README.md
)

echo.
echo [7/7] Creating restructure log...

REM Create log file
echo FlashEASuite V2 - Restructure Log > RESTRUCTURE_LOG.txt
echo Date: %DATE% %TIME% >> RESTRUCTURE_LOG.txt
echo ================================== >> RESTRUCTURE_LOG.txt
echo. >> RESTRUCTURE_LOG.txt
echo Actions completed: >> RESTRUCTURE_LOG.txt
echo - Created Tester\ directory >> RESTRUCTURE_LOG.txt
echo - Moved test files to Tester\ >> RESTRUCTURE_LOG.txt
echo - Updated Day 1 Risk Management files >> RESTRUCTURE_LOG.txt
echo - Deleted .zip archives >> RESTRUCTURE_LOG.txt
echo - Deleted duplicate .bat files >> RESTRUCTURE_LOG.txt
echo - Updated documentation >> RESTRUCTURE_LOG.txt
echo - Created new documentation files >> RESTRUCTURE_LOG.txt
echo. >> RESTRUCTURE_LOG.txt
echo Status: COMPLETE >> RESTRUCTURE_LOG.txt

echo     - Created RESTRUCTURE_LOG.txt

echo.
echo ================================================================
echo   RESTRUCTURE COMPLETE!
echo ================================================================
echo.
echo Summary:
echo   - Tester\ directory created
echo   - All test files moved to Tester\
echo   - Day 1 files updated
echo   - ZIP archives cleaned
echo   - Duplicate .bat files removed
echo   - Documentation updated
echo.
echo Next steps:
echo   1. Open MetaEditor
echo   2. Compile tests in Tester\
echo   3. Run test_integration_day1
echo   4. Verify 100%% pass rate
echo.
echo See RESTRUCTURE_LOG.txt for details.
echo.

REM Clean up restructure package
if exist "Restructure_Package" (
    echo Cleaning up restructure package...
    rmdir /S /Q "Restructure_Package" >nul 2>&1
)

pause
