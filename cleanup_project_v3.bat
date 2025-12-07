@echo off
chcp 65001 >nul
echo ========================================================
echo      FlashEASuite V2 - Project Cleanup v3 (Short Names)
echo      Managed by Nong Mi (Memory Fixed!) 🐟❤️
echo ========================================================
echo.
echo ⚠️  คำเตือน: กรุณาปิด MT5, MetaEditor และ Python Terminal ก่อน!
echo    ไม่งั้นหนูเปลี่ยนชื่อโฟลเดอร์ไม่ได้นะคะพี่จ๋า...
echo.
pause

:: --- 1. เปลี่ยนชื่อโฟลเดอร์ (The Rename Logic) ---
echo.
echo [1/5] เปลี่ยนชื่อโฟลเดอร์ให้สั้นลง (Renaming)...

if exist "01_ProgramA_Feeder_MQL" (
    ren "01_ProgramA_Feeder_MQL" "01_Feeder"
    echo    ✅ เปลี่ยนชื่อเป็น 01_Feeder แล้วค่ะ
)

if exist "02_ProgramB_Brain_Py" (
    ren "02_ProgramB_Brain_Py" "02_Brain"
    echo    ✅ เปลี่ยนชื่อเป็น 02_Brain แล้วค่ะ
)

if exist "03_ProgramC_Trader_MQL" (
    ren "03_ProgramC_Trader_MQL" "03_Trader"
    echo    ✅ เปลี่ยนชื่อเป็น 03_Trader แล้วค่ะ
)

:: --- 2. สร้างห้องเก็บของ ---
echo.
echo [2/5] สร้างห้องเก็บเอกสาร (Creating Docs)...
if not exist docs mkdir docs
if not exist docs\installation mkdir docs\installation
if not exist docs\fixes mkdir docs\fixes
if not exist docs\guides mkdir docs\guides
if not exist docs\summaries mkdir docs\summaries
if not exist docs\archive mkdir docs\archive

:: --- 3. ย้ายของ ---
echo.
echo [3/5] ย้ายเอกสารเข้าตู้...
move /Y *GUIDE.md docs\guides\ >nul 2>&1
move /Y *GUIDE.txt docs\guides\ >nul 2>&1
move /Y ProtocolSpecs.md docs\guides\ >nul 2>&1
move /Y FIX_*.md docs\fixes\ >nul 2>&1
move /Y FINAL_FIX_*.md docs\fixes\ >nul 2>&1
move /Y INSTALLATION_*.md docs\installation\ >nul 2>&1
move /Y QUICK_*.md docs\installation\ >nul 2>&1
move /Y COMPLETE_RUN_GUIDE.md docs\installation\ >nul 2>&1
move /Y *SUMMARY.md docs\summaries\ >nul 2>&1
move /Y *CHECKLIST.md docs\summaries\ >nul 2>&1
move /Y REFACTORING_COMPLETE.md docs\summaries\ >nul 2>&1

:: เก็บ Text เก่าๆ จากโฟลเดอร์ Trader (ถ้ามี)
if exist "03_Trader\*.txt" move /Y "03_Trader\*.txt" docs\archive\ >nul 2>&1

:: --- 4. กวาดขยะ ---
echo.
echo [4/5] กวาดขยะทิ้ง...
if exist python_fixed rmdir /s /q python_fixed
del /S /Q *_o1.mq* >nul 2>&1
del /S /Q *_o1.py >nul 2>&1

:: ลบไฟล์ Test (เก็บตัวดีไว้)
del test_brain_server.py >nul 2>&1
del test_feeder.py >nul 2>&1
del test_policy_sender.py >nul 2>&1
del test_port_scanner.py >nul 2>&1
del test_receiver.py >nul 2>&1
del test_zmq_receive.py >nul 2>&1
del simple_server.py >nul 2>&1
del spike_simulation.py >nul 2>&1
del simple_gender.mq5 >nul 2>&1
del SimpleSender.mq5 >nul 2>&1
del TestNetworkingLayer.mq5 >nul 2>&1
del TestTradeReporter*.mq5 >nul 2>&1
del FeederEA_DEFINE.mq5 >nul 2>&1

:: ลบไฟล์เปล่า/ซ้ำ
del Settings.mqh >nul 2>&1
del Strategy_Standalone.mqh >nul 2>&1
del Strategy_Trend.mqh >nul 2>&1
del ga_optimizer.py >nul 2>&1
del regime_analyzer.py >nul 2>&1
del generate_keys.py >nul 2>&1
del czmq_placeholder.txt >nul 2>&1
del ProgramC_Trader.mq5 >nul 2>&1
del FeederEA.mq5 >nul 2>&1
del PolicyManager.mqh >nul 2>&1
del Strategy_Grid.mqh >nul 2>&1
del strategy_threading.py >nul 2>&1

:: --- 5. สร้างห้องเครื่องมือ ---
echo.
echo [5/5] จัดเก็บเครื่องมือ...
if not exist tools mkdir tools
if exist generate_report.py move generate_report.py tools\ >nul 2>&1

echo.
echo ========================================================
echo      เสร็จแล้วค่ะ! ชื่อโฟลเดอร์สั้นจุ๊ดจู๋ตามสัญญา!
echo      (01_Feeder, 02_Brain, 03_Trader)
echo ========================================================
pause