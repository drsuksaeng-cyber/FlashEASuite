@echo off
echo ========================================================
echo FlashEASuite V2 - Module Installation v3 (Short Names)
echo Managed by Nong Mi (Fixed Paths!) ❤️
echo ========================================================
echo.
echo [CHECK] ตรวจสอบโฟลเดอร์เป้าหมาย (ต้องเป็นชื่อสั้นแล้ว)...

:: เช็คว่าพี่รัน Cleanup เปลี่ยนชื่อไปหรือยัง
if not exist "02_Brain" (
    echo [ERROR] ไม่เจอโฟลเดอร์ '02_Brain'
    echo         พี่จ๋าต้องรัน 'cleanup_project_v3.bat' ก่อนนะคะ!
    pause
    exit /b
)

echo    [OK] เจอโฟลเดอร์ 02_Brain แล้วค่ะ (พร้อมเสียบ!)
pause

echo.
echo [1/3] เตรียมพื้นที่ (Creating Folders)...

:: 1. Python Strategy (ลงใน 02_Brain)
if not exist "02_Brain\core\strategy" (
    mkdir "02_Brain\core\strategy"
    echo    ✅ สร้างห้อง 02_Brain\core\strategy\ แล้วค่ะ
)

:: 2. MQL5 Protocol
if not exist "Include\Network\Protocol" (
    mkdir "Include\Network\Protocol"
    echo    ✅ สร้างห้อง Include\Network\Protocol\ แล้วค่ะ
)

:: 3. MQL5 Grid
if not exist "Include\Logic\Grid" (
    mkdir "Include\Logic\Grid"
    echo    ✅ สร้างห้อง Include\Logic\Grid\ แล้วค่ะ
)

echo.
echo [2/3] เริ่มติดตั้งไฟล์ (Installing)...

:: Install Python
echo    ... กำลังก๊อปปี้ Python Strategy
xcopy /s /y /q "python_strategy\*" "02_Brain\core\strategy\" >nul
echo    ✅ เรียบร้อย!

:: Install Protocol
echo    ... กำลังก๊อปปี้ Protocol
copy /y "mql_protocol\Definitions.mqh" "Include\Network\Protocol\" >nul
copy /y "mql_protocol\Serialization.mqh" "Include\Network\Protocol\" >nul
copy /y "mql_protocol\Protocol.mqh" "Include\Network\" >nul
echo    ✅ เรียบร้อย!

:: Install Grid
echo    ... กำลังก๊อปปี้ Grid Strategy
copy /y "mql_grid\GridConfig.mqh" "Include\Logic\Grid\" >nul
copy /y "mql_grid\GridState.mqh" "Include\Logic\Grid\" >nul
copy /y "mql_grid\GridCore.mqh" "Include\Logic\Grid\" >nul
copy /y "mql_grid\Strategy_Grid.mqh" "Include\Logic\" >nul
echo    ✅ เรียบร้อย!

echo.
echo [3/3] เก็บกวาดงาน (Finalizing)...
:: Rename old strategy.py to avoid confusion
if exist "02_Brain\core\strategy.py" (
    ren "02_Brain\core\strategy.py" "strategy_old_backup.py"
    echo    ✅ เปลี่ยนชื่อไฟล์เก่าเป็น strategy_old_backup.py ให้แล้วค่ะ
)

echo.
echo ========================================================
echo      เสร็จสมบูรณ์แล้วค่ะพี่จ๋า! (Nong Mi Loves You!)
echo      (โฟลเดอร์ชื่อสั้น + ไฟล์ครบ + พร้อมรัน!)
echo ========================================================
pause