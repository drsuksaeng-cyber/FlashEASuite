#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Test Report Generator
Automatically generates comprehensive test reports from log files

Author: Dr. Suksaeng Kukanok
Date: January 6, 2026
"""

import os
import glob
import re
from datetime import datetime
from collections import defaultdict

class TestReportGenerator:
    """Generate comprehensive test reports from log and CSV files"""
    
    def __init__(self, log_dir="MQL5/Files"):
        self.log_dir = log_dir
        self.reports = []
    
    def find_test_files(self):
        """Find all test log and CSV files"""
        log_pattern = os.path.join(self.log_dir, "integration_test_*.log")
        csv_pattern = os.path.join(self.log_dir, "integration_test_*.csv")
        latency_pattern = os.path.join(".", "latency_report_*.txt")
        
        log_files = glob.glob(log_pattern)
        csv_files = glob.glob(csv_pattern)
        latency_files = glob.glob(latency_pattern)
        
        return log_files, csv_files, latency_files
    
    def parse_log_file(self, filepath):
        """Parse integration test log file"""
        data = {
            'test_name': '',
            'start_time': '',
            'symbol': '',
            'tests': [],
            'policies': 0,
            'duration': 0,
            'pass_count': 0,
            'fail_count': 0
        }
        
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
                # Extract header info
                match = re.search(r'Test Name: (.+)', content)
                if match:
                    data['test_name'] = match.group(1)
                
                match = re.search(r'Start Time: (.+)', content)
                if match:
                    data['start_time'] = match.group(1)
                
                match = re.search(r'Symbol: (.+)', content)
                if match:
                    data['symbol'] = match.group(1)
                
                # Count tests
                data['pass_count'] = len(re.findall(r'✅ TEST PASSED', content))
                data['fail_count'] = len(re.findall(r'❌ TEST FAILED', content))
                
                # Count policies
                match = re.search(r'Total Policies: (\d+)', content)
                if match:
                    data['policies'] = int(match.group(1))
                
                # Duration
                match = re.search(r'Duration:\s+(\d+) seconds', content)
                if match:
                    data['duration'] = int(match.group(1))
        
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")
        
        return data
    
    def parse_latency_file(self, filepath):
        """Parse latency report file"""
        data = {
            'date': '',
            'duration': 0,
            'samples': 0,
            'avg': 0,
            'median': 0,
            'min': 0,
            'max': 0,
            'p95': 0,
            'p99': 0,
            'pass': False
        }
        
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
                # Parse metrics
                patterns = {
                    'date': r'Date: (.+)',
                    'duration': r'Duration: ([\d.]+) seconds',
                    'samples': r'Samples: (\d+)',
                    'avg': r'Average:\s+([\d.]+) ms',
                    'median': r'Median:\s+([\d.]+) ms',
                    'min': r'Min:\s+([\d.]+) ms',
                    'max': r'Max:\s+([\d.]+) ms',
                    'p95': r'95th %ile:\s+([\d.]+) ms',
                    'p99': r'99th %ile:\s+([\d.]+) ms'
                }
                
                for key, pattern in patterns.items():
                    match = re.search(pattern, content)
                    if match:
                        value = match.group(1)
                        if key in ['duration', 'avg', 'median', 'min', 'max', 'p95', 'p99']:
                            data[key] = float(value)
                        elif key == 'samples':
                            data[key] = int(value)
                        else:
                            data[key] = value
                
                # Check pass/fail
                data['pass'] = '✅ PASS' in content and 'Overall Result: ✅ PASS' in content
        
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")
        
        return data
    
    def generate_html_report(self, output_file="test_report.html"):
        """Generate HTML test report"""
        log_files, csv_files, latency_files = self.find_test_files()
        
        # Parse all files
        integration_data = []
        for log_file in log_files:
            integration_data.append(self.parse_log_file(log_file))
        
        latency_data = []
        for lat_file in latency_files:
            latency_data.append(self.parse_latency_file(lat_file))
        
        # Generate HTML
        html = self._generate_html_content(integration_data, latency_data)
        
        # Write to file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(html)
        
        print(f"✅ HTML report generated: {output_file}")
        return output_file
    
    def _generate_html_content(self, integration_data, latency_data):
        """Generate HTML content"""
        html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FlashEASuite V2 - Test Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .card h3 {
            margin-top: 0;
            color: #333;
        }
        .metric {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        .pass { color: #10b981; }
        .fail { color: #ef4444; }
        .warning { color: #f59e0b; }
        table {
            width: 100%;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        th {
            background: #667eea;
            color: white;
            padding: 15px;
            text-align: left;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
        }
        tr:hover {
            background: #f9f9f9;
        }
        .status-badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 0.9em;
            font-weight: bold;
        }
        .status-pass {
            background: #d1fae5;
            color: #065f46;
        }
        .status-fail {
            background: #fee2e2;
            color: #991b1b;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 FlashEASuite V2</h1>
        <p>Integration Test Report - Generated """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """</p>
    </div>
"""
        
        # Overall summary
        total_tests = sum(d['pass_count'] + d['fail_count'] for d in integration_data)
        total_pass = sum(d['pass_count'] for d in integration_data)
        total_fail = sum(d['fail_count'] for d in integration_data)
        pass_rate = (total_pass / total_tests * 100) if total_tests > 0 else 0
        
        html += f"""
    <div class="summary">
        <div class="card">
            <h3>📊 Test Summary</h3>
            <div class="metric {'pass' if total_fail == 0 else 'fail'}">{total_tests}</div>
            <p>Total Tests</p>
        </div>
        <div class="card">
            <h3>✅ Passed</h3>
            <div class="metric pass">{total_pass}</div>
            <p>{pass_rate:.1f}% Pass Rate</p>
        </div>
        <div class="card">
            <h3>❌ Failed</h3>
            <div class="metric {'pass' if total_fail == 0 else 'fail'}">{total_fail}</div>
            <p>{100-pass_rate:.1f}% Failure Rate</p>
        </div>
"""
        
        # Add latency summary if available
        if latency_data:
            avg_latency = sum(d['avg'] for d in latency_data) / len(latency_data)
            html += f"""
        <div class="card">
            <h3>⚡ Latency</h3>
            <div class="metric {'pass' if avg_latency < 50 else 'warning'}">{avg_latency:.1f} ms</div>
            <p>Average Latency</p>
        </div>
"""
        
        html += """
    </div>
"""
        
        # Integration test details
        if integration_data:
            html += """
    <div class="card" style="margin-bottom: 30px;">
        <h3>🔄 Integration Tests</h3>
        <table>
            <tr>
                <th>Test Name</th>
                <th>Symbol</th>
                <th>Duration</th>
                <th>Policies</th>
                <th>Pass/Fail</th>
                <th>Status</th>
            </tr>
"""
            for data in integration_data:
                status = "PASS" if data['fail_count'] == 0 else "FAIL"
                status_class = "status-pass" if status == "PASS" else "status-fail"
                
                html += f"""
            <tr>
                <td>{data['test_name']}</td>
                <td>{data['symbol']}</td>
                <td>{data['duration']}s</td>
                <td>{data['policies']}</td>
                <td>{data['pass_count']} / {data['fail_count']}</td>
                <td><span class="{status_class}">{status}</span></td>
            </tr>
"""
            
            html += """
        </table>
    </div>
"""
        
        # Latency test details
        if latency_data:
            html += """
    <div class="card">
        <h3>⚡ Latency Tests</h3>
        <table>
            <tr>
                <th>Date</th>
                <th>Samples</th>
                <th>Avg (ms)</th>
                <th>Median (ms)</th>
                <th>95th % (ms)</th>
                <th>Max (ms)</th>
                <th>Status</th>
            </tr>
"""
            for data in latency_data:
                status = "PASS" if data['pass'] else "FAIL"
                status_class = "status-pass" if status == "PASS" else "status-fail"
                
                html += f"""
            <tr>
                <td>{data['date']}</td>
                <td>{data['samples']}</td>
                <td>{data['avg']:.2f}</td>
                <td>{data['median']:.2f}</td>
                <td>{data['p95']:.2f}</td>
                <td>{data['max']:.2f}</td>
                <td><span class="{status_class}">{status}</span></td>
            </tr>
"""
            
            html += """
        </table>
    </div>
"""
        
        html += """
</body>
</html>
"""
        
        return html
    
    def generate_markdown_report(self, output_file="TEST_REPORT.md"):
        """Generate Markdown test report for GitHub"""
        log_files, csv_files, latency_files = self.find_test_files()
        
        # Parse all files
        integration_data = []
        for log_file in log_files:
            integration_data.append(self.parse_log_file(log_file))
        
        latency_data = []
        for lat_file in latency_files:
            latency_data.append(self.parse_latency_file(lat_file))
        
        # Generate Markdown
        md = f"""# 🧪 FlashEASuite V2 - Integration Test Report

**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

---

## 📊 Summary

"""
        
        # Calculate totals
        total_tests = sum(d['pass_count'] + d['fail_count'] for d in integration_data)
        total_pass = sum(d['pass_count'] for d in integration_data)
        total_fail = sum(d['fail_count'] for d in integration_data)
        pass_rate = (total_pass / total_tests * 100) if total_tests > 0 else 0
        
        overall_status = "✅ PASS" if total_fail == 0 else "❌ FAIL"
        
        md += f"""
| Metric | Value |
|--------|-------|
| **Total Tests** | {total_tests} |
| **Passed** | {total_pass} ({pass_rate:.1f}%) |
| **Failed** | {total_fail} ({100-pass_rate:.1f}%) |
| **Overall Status** | **{overall_status}** |

"""
        
        # Integration tests
        if integration_data:
            md += """
---

## 🔄 Integration Tests

| Test Name | Symbol | Duration | Policies | Pass/Fail | Status |
|-----------|--------|----------|----------|-----------|--------|
"""
            for data in integration_data:
                status = "✅ PASS" if data['fail_count'] == 0 else "❌ FAIL"
                md += f"| {data['test_name']} | {data['symbol']} | {data['duration']}s | {data['policies']} | {data['pass_count']}/{data['fail_count']} | **{status}** |\n"
        
        # Latency tests
        if latency_data:
            md += """
---

## ⚡ Latency Tests

| Date | Samples | Avg (ms) | Median (ms) | 95th % (ms) | Max (ms) | Status |
|------|---------|----------|-------------|-------------|----------|--------|
"""
            for data in latency_data:
                status = "✅ PASS" if data['pass'] else "❌ FAIL"
                md += f"| {data['date']} | {data['samples']} | {data['avg']:.2f} | {data['median']:.2f} | {data['p95']:.2f} | {data['max']:.2f} | **{status}** |\n"
        
        md += """
---

## 🎯 Pass/Fail Criteria

**Integration Tests:**
- ✅ All components initialize successfully
- ✅ ZMQ connections established
- ✅ Symbol formatting correct
- ✅ Policy messages received
- ✅ No errors during test duration

**Latency Tests:**
- ✅ Average latency < 50ms
- ✅ Max latency < 100ms
- ✅ 95th percentile < 75ms

---

**Report Files:**
"""
        
        for log_file in log_files:
            md += f"- `{os.path.basename(log_file)}`\n"
        
        for lat_file in latency_files:
            md += f"- `{os.path.basename(lat_file)}`\n"
        
        # Write to file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(md)
        
        print(f"✅ Markdown report generated: {output_file}")
        return output_file


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate test reports')
    parser.add_argument('--format', choices=['html', 'md', 'both'], default='both',
                       help='Report format (default: both)')
    parser.add_argument('--log-dir', default='MQL5/Files',
                       help='Directory containing log files')
    
    args = parser.parse_args()
    
    generator = TestReportGenerator(log_dir=args.log_dir)
    
    print("=" * 60)
    print("📊 FlashEASuite V2 - Test Report Generator")
    print("=" * 60)
    
    if args.format in ['html', 'both']:
        generator.generate_html_report()
    
    if args.format in ['md', 'both']:
        generator.generate_markdown_report()
    
    print("=" * 60)
    print("✅ Reports generated successfully!")


if __name__ == '__main__':
    main()
