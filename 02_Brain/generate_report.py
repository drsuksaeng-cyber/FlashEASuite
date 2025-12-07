"""
FlashEASuite V2 - Reporting Module 📊
Generate beautiful Excel reports from MQL5 CSV data (Common Folder)
"""

import pandas as pd
import glob
import os
from datetime import datetime
import matplotlib.pyplot as plt

# --- [ส่วนตั้งค่า Path อัตโนมัติ] ---
# ดึง Path ของ AppData (เช่น C:\Users\YourName\AppData\Roaming)
app_data = os.getenv('APPDATA')

# สร้าง Path ไปยัง Common Files ของ MT5 (มาตรฐานของ MetaQuotes)
MT5_COMMON_PATH = os.path.join(app_data, "MetaQuotes", "Terminal", "Common", "Files", "FlashEA")

# สร้างโฟลเดอร์เก็บรายงานในฝั่ง Python ถ้ายังไม่มี
REPORT_OUTPUT_DIR = "reports"
if not os.path.exists(REPORT_OUTPUT_DIR):
    os.makedirs(REPORT_OUTPUT_DIR)

def generate_report():
    print("="*60)
    print("📊 FlashEASuite V2: Report Generator")
    print(f"📂 Searching for data in: {MT5_COMMON_PATH}")
    print("="*60)
    
    # 1. ค้นหาไฟล์ DailyReport ทั้งหมด
    # (ชื่อไฟล์จาก MQL5: DailyReport_2025.csv หรือตามปี)
    search_pattern = os.path.join(MT5_COMMON_PATH, "DailyReport_*.csv")
    csv_files = glob.glob(search_pattern)
    
    if not csv_files:
        print(f"❌ No DailyReport CSV files found in: {MT5_COMMON_PATH}")
        print("   -> Please check if MQL5 'CDailyStats' initialized correctly.")
        print("   -> Check if 'FILE_COMMON' is used in MQL5.")
        return

    print(f"✅ Found {len(csv_files)} report files.")
    
    # 2. อ่านและรวมข้อมูลทั้งหมด
    all_data = []
    for file in csv_files:
        try:
            print(f"   Reading: {os.path.basename(file)}...")
            df = pd.read_csv(file)
            all_data.append(df)
        except Exception as e:
            print(f"   ⚠️ Error reading {file}: {e}")
            
    if not all_data:
        print("❌ No valid data to process.")
        return

    full_df = pd.concat(all_data, ignore_index=True)
    
    # แปลงคอลัมน์วันที่
    try:
        full_df['Date'] = pd.to_datetime(full_df['Date'])
    except Exception as e:
        print(f"⚠️ Date conversion warning: {e}")
        full_df['Date'] = pd.to_datetime(full_df['Date'], errors='coerce')
        full_df = full_df.dropna(subset=['Date'])

    # เรียงตามวันที่
    full_df = full_df.sort_values('Date')
    
    # คำนวณกำไรสะสม
    full_df['Cumulative_Profit'] = full_df['Profit'].cumsum()

    # 3. สร้างกราฟ (Visualization)
    print("🎨 Generating charts...")
    plt.style.use('ggplot') # เปลี่ยน Style ให้ดูทันสมัย
    
    # --- กราฟ 1: Equity Curve ---
    plt.figure(figsize=(10, 6))
    plt.plot(full_df['Date'], full_df['Cumulative_Profit'], label='Total Profit ($)', color='green', linewidth=2)
    plt.fill_between(full_df['Date'], full_df['Cumulative_Profit'], color='green', alpha=0.1) # ระบายสีใต้กราฟ
    plt.title('Portfolio Performance (Equity Curve)')
    plt.xlabel('Date')
    plt.ylabel('Cumulative Profit ($)')
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    
    equity_chart_path = os.path.join(REPORT_OUTPUT_DIR, 'chart_equity_curve.png')
    plt.savefig(equity_chart_path)
    plt.close()
    
    # --- กราฟ 2: Daily Profit/Loss ---
    plt.figure(figsize=(10, 6))
    colors = ['red' if x < 0 else 'blue' for x in full_df['Profit']]
    plt.bar(full_df['Date'], full_df['Profit'], color=colors)
    plt.title('Daily Profit/Loss')
    plt.xlabel('Date')
    plt.ylabel('Profit ($)')
    plt.axhline(y=0, color='black', linestyle='-', linewidth=0.5)
    plt.tight_layout()
    
    pnl_chart_path = os.path.join(REPORT_OUTPUT_DIR, 'chart_daily_pnl.png')
    plt.savefig(pnl_chart_path)
    plt.close()

    # 4. ส่งออกเป็น Excel
    timestamp_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = os.path.join(REPORT_OUTPUT_DIR, f"FlashEA_Report_{timestamp_str}.xlsx")
    
    print(f"💾 Saving Excel report to: {output_file}")
    
    try:
        with pd.ExcelWriter(output_file, engine='xlsxwriter') as writer:
            # Sheet 1: Daily Data
            full_df.to_excel(writer, sheet_name='Daily_Data', index=False)
            
            workbook  = writer.book
            worksheet = writer.sheets['Daily_Data']
            worksheet.set_column('A:A', 20)
            
            # Sheet 2: Summary
            total_profit = full_df['Profit'].sum()
            total_trades = full_df['Trades'].sum()
            avg_win_rate = full_df['WinRate%'].mean() if 'WinRate%' in full_df.columns else 0
            max_dd = full_df['DailyDD%'].max() if 'DailyDD%' in full_df.columns else 0
            
            summary_data = {
                'Metric': ['Total Profit', 'Total Trades', 'Average Win Rate', 'Max Daily Drawdown'],
                'Value': [
                    f"${total_profit:,.2f}",
                    int(total_trades),
                    f"{avg_win_rate:.2f}%",
                    f"{max_dd:.2f}%"
                ]
            }
            
            summary_df = pd.DataFrame(summary_data)
            summary_df.to_excel(writer, sheet_name='Summary', index=False)
            
            # Formats
            bold_fmt = workbook.add_format({'bold': True})
            worksheet_summary = writer.sheets['Summary']
            worksheet_summary.set_column('A:A', 20)
            worksheet_summary.set_column('B:B', 15)
            
            # Sheet 3: Charts
            worksheet_charts = workbook.add_worksheet('Charts')
            worksheet_charts.write('A1', 'Equity Curve', bold_fmt)
            worksheet_charts.insert_image('A3', equity_chart_path)
            
            worksheet_charts.write('A35', 'Daily Profit/Loss', bold_fmt)
            worksheet_charts.insert_image('A37', pnl_chart_path)
            
        print(f"✅ Report generation completed successfully!")
        print(f"   -> Report File: {output_file}")
        
    except Exception as e:
        print(f"❌ Error saving Excel file: {e}")
        print("   (Please close the Excel file if it's open)")

if __name__ == "__main__":
    # Auto-install dependencies if missing
    try:
        import xlsxwriter
        import matplotlib
        import openpyxl
    except ImportError as e:
        print(f"⚠️ Missing library: {e.name}")
        os.system("pip install pandas matplotlib xlsxwriter openpyxl")
        print("--- Libraries installed. Please run again ---")
    else:
        generate_report()