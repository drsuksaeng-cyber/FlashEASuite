@echo off
echo ========================================
echo FlashEASuite V2 - Installation Script
echo ========================================
echo.

REM Check if files exist
if not exist "Strategy_Grid.mqh" (
    echo ERROR: Strategy_Grid.mqh not found!
    pause
    exit /b 1
)

if not exist "PolicyManager.mqh" (
    echo ERROR: PolicyManager.mqh not found!
    pause
    exit /b 1
)

if not exist "ProgramC_Trader.mq5" (
    echo ERROR: ProgramC_Trader.mq5 not found!
    pause
    exit /b 1
)

echo Step 1: Copying MQL5 files...
copy /Y Strategy_Grid.mqh "Include\Logic\Strategy_Grid.mqh"
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy Strategy_Grid.mqh
    pause
    exit /b 1
)
echo [OK] Strategy_Grid.mqh

copy /Y PolicyManager.mqh "Include\Logic\PolicyManager.mqh"
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy PolicyManager.mqh
    pause
    exit /b 1
)
echo [OK] PolicyManager.mqh

copy /Y ProgramC_Trader.mq5 "ProgramC_Trader.mq5"
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy ProgramC_Trader.mq5
    pause
    exit /b 1
)
echo [OK] ProgramC_Trader.mq5

echo.
echo ========================================
echo Installation Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Open MetaEditor
echo 2. Open ProgramC_Trader.mq5
echo 3. Press F7 to compile
echo.
echo Expected: 0 error(s), 0 warning(s)
echo.
pause
