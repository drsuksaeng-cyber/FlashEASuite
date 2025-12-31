"""
Streamlit HTML Report Printer Module
Uses hidden iframe technique to print without disrupting Streamlit UI
"""

import streamlit as st
import streamlit.components.v1 as components


def print_html_report(html_content: str) -> None:
    """
    Print HTML report using hidden iframe technique.
    
    Args:
        html_content: The HTML content to print (body content only, no <html> tags)
    """
    
    # Escape the HTML content for safe JavaScript injection
    escaped_html = html_content.replace('\\', '\\\\').replace('`', '\\`').replace('$', '\\$')
    
    # JavaScript code to create hidden iframe and print
    print_js = f"""
    <script>
    function printReport() {{
        // Create hidden iframe
        const iframe = document.createElement('iframe');
        iframe.style.position = 'absolute';
        iframe.style.width = '0px';
        iframe.style.height = '0px';
        iframe.style.border = 'none';
        iframe.style.visibility = 'hidden';
        
        document.body.appendChild(iframe);
        
        // Full HTML document with styling
        const htmlDoc = `
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        @page {{
            margin: 2cm;
            @bottom-right {{
                content: "Page " counter(page);
                font-family: 'Sarabun', sans-serif;
                font-size: 12pt;
            }}
        }}
        
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Sarabun', sans-serif;
            font-size: 16pt;
            line-height: 1.6;
            color: #000;
            background: white;
            padding: 20px;
        }}
        
        h1, h2, h3, h4, h5, h6 {{
            font-family: 'Sarabun', sans-serif;
            font-weight: 600;
            margin-bottom: 12pt;
            margin-top: 16pt;
        }}
        
        h1 {{ font-size: 24pt; }}
        h2 {{ font-size: 20pt; }}
        h3 {{ font-size: 18pt; }}
        
        p {{
            margin-bottom: 10pt;
        }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 15pt 0;
            font-size: 16pt;
            border: 1px solid black;
        }}
        
        th, td {{
            border: 1px solid black;
            padding: 8pt 12pt;
            text-align: left;
        }}
        
        th {{
            background-color: #f0f0f0;
            font-weight: 600;
        }}
        
        tr:nth-child(even) {{
            background-color: #fafafa;
        }}
        
        img {{
            max-width: 100%;
            height: auto;
        }}
        
        .page-break {{
            page-break-after: always;
        }}
        
        @media print {{
            body {{
                print-color-adjust: exact;
                -webkit-print-color-adjust: exact;
            }}
        }}
    </style>
</head>
<body>
{escaped_html}
</body>
</html>
        `;
        
        // Write content to iframe
        const iframeDoc = iframe.contentWindow.document;
        iframeDoc.open();
        iframeDoc.write(htmlDoc);
        iframeDoc.close();
        
        // Wait for content to load, then print
        iframe.onload = function() {{
            setTimeout(() => {{
                try {{
                    iframe.contentWindow.focus();
                    iframe.contentWindow.print();
                    
                    // Clean up after printing (or cancel)
                    setTimeout(() => {{
                        document.body.removeChild(iframe);
                    }}, 1000);
                }} catch (e) {{
                    console.error('Print error:', e);
                    document.body.removeChild(iframe);
                }}
            }}, 500);
        }};
    }}
    
    // Execute print function
    printReport();
    </script>
    """
    
    # Inject JavaScript into Streamlit
    components.html(print_js, height=0)


# ============================================================================
# TEST BLOCK
# ============================================================================
if __name__ == "__main__":
    st.set_page_config(page_title="HTML Report Printer Test", layout="wide")
    
    st.title("🖨️ HTML Report Printer Test")
    st.markdown("---")
    
    # Dummy HTML content for testing
    dummy_html = """
    <h1>รายงานการทดสอบระบบพิมพ์ (Test Report)</h1>
    <p><strong>วันที่:</strong> 27 ธันวาคม 2568</p>
    <p><strong>ผู้จัดทำ:</strong> Dr. Suksaeng Kukanok</p>
    
    <h2>1. ข้อมูลทั่วไป (General Information)</h2>
    <p>This is a test report to verify the Sarabun font rendering at <strong>16pt</strong> size. 
    The text should be clear and readable when printed on paper.</p>
    <p>นี่คือรายงานทดสอบเพื่อตรวจสอบการแสดงผลฟอนต์ Sarabun ที่ขนาด 16pt 
    ข้อความควรชัดเจนและอ่านง่ายเมื่อพิมพ์ออกกระดาษ</p>
    
    <h2>2. ตารางข้อมูลตัวอย่าง (Sample Data Table)</h2>
    <table>
        <thead>
            <tr>
                <th>ลำดับ</th>
                <th>รายการ (Item)</th>
                <th>ค่า (Value)</th>
                <th>หมายเหตุ (Note)</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>1</td>
                <td>Font Family</td>
                <td>Sarabun</td>
                <td>Google Fonts</td>
            </tr>
            <tr>
                <td>2</td>
                <td>Font Size</td>
                <td>16pt</td>
                <td>Body Text</td>
            </tr>
            <tr>
                <td>3</td>
                <td>Border Style</td>
                <td>1px solid black</td>
                <td>Tables</td>
            </tr>
            <tr>
                <td>4</td>
                <td>Page Numbers</td>
                <td>Bottom-right</td>
                <td>Auto-generated</td>
            </tr>
        </tbody>
    </table>
    
    <h2>3. รายละเอียดเพิ่มเติม (Additional Details)</h2>
    <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor 
    incididunt ut labore et dolore magna aliqua.</p>
    <p>ข้อความภาษาไทยเพื่อทดสอบการแสดงผลฟอนต์ Sarabun ในรายงาน 
    ควรมีความชัดเจนและสวยงามทั้งในหน้าจอและเมื่อพิมพ์ออกมา</p>
    
    <h3>3.1 รายการตรวจสอบ (Checklist)</h3>
    <table>
        <thead>
            <tr>
                <th style="width: 50%;">รายการ</th>
                <th style="width: 20%;">สถานะ</th>
                <th style="width: 30%;">ผลการทดสอบ</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Sarabun font loads correctly</td>
                <td>✓</td>
                <td>Pass</td>
            </tr>
            <tr>
                <td>16pt body text size</td>
                <td>✓</td>
                <td>Pass</td>
            </tr>
            <tr>
                <td>Black table borders</td>
                <td>✓</td>
                <td>Pass</td>
            </tr>
            <tr>
                <td>Page numbers display</td>
                <td>✓</td>
                <td>Pass</td>
            </tr>
            <tr>
                <td>Streamlit UI preserved</td>
                <td>✓</td>
                <td>Pass</td>
            </tr>
        </tbody>
    </table>
    
    <div class="page-break"></div>
    
    <h2>Page 2 - Continuation</h2>
    <p>This content appears on the second page to test page numbering functionality.</p>
    <p>หน้าที่สองเพื่อทดสอบการแสดงเลขหน้าอัตโนมัติ</p>
    
    <h3>Summary Table</h3>
    <table>
        <thead>
            <tr>
                <th>Feature</th>
                <th>Implementation</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Hidden Iframe Technique</td>
                <td>JavaScript injection</td>
                <td>✅ Working</td>
            </tr>
            <tr>
                <td>UI Preservation</td>
                <td>No document.write()</td>
                <td>✅ Working</td>
            </tr>
            <tr>
                <td>Font Loading</td>
                <td>Google Fonts CDN</td>
                <td>✅ Working</td>
            </tr>
        </tbody>
    </table>
    """
    
    # Display preview
    st.subheader("📄 Report Preview")
    with st.expander("Show HTML Preview", expanded=False):
        st.markdown(dummy_html, unsafe_allow_html=True)
    
    st.markdown("---")
    
    # Print button
    col1, col2, col3 = st.columns([1, 1, 1])
    with col2:
        if st.button("🖨️ Print Report", type="primary", use_container_width=True):
            st.success("✅ Opening print dialog...")
            print_html_report(dummy_html)
            st.info("💡 After printing, verify:\n"
                   "- Font is Sarabun\n"
                   "- Text size is 16pt\n"
                   "- Tables have black borders\n"
                   "- Page numbers appear at bottom-right\n"
                   "- Streamlit buttons still work!")