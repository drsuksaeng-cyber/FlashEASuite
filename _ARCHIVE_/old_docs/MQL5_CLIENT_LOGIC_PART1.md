# 🔧 **MQL5 Client Logic - Complete Specification**

**Version:** 1.0  
**Date:** December 22, 2025  
**Component:** MQL5 Client (HMA + Linear Regression + Grid Integration)  
**Status:** 📋 For Review & Critique

---

## 📋 **Table of Contents**

1. [Overall Architecture](#architecture)
2. [Component 1: HMA + Linear Regression](#hma-linreg)
3. [Component 2: Server Signal Handler](#server-handler)
4. [Component 3: Grid Integration](#grid-integration)
5. [Component 4: Magic Number Management](#magic-number)
6. [Component 5: TransferToGrid Emergency](#transfer-grid)
7. [Complete Logic Flow](#logic-flow)
8. [Parameters & Thresholds](#parameters)
9. [Testing Strategy](#testing)
10. [Message Format](#messages)

---

<a name="architecture"></a>
## 🏗️ **1. Overall Architecture**

### **High-Level Design**

```
┌─────────────────────────────────────────────────────────────┐
│                   MQL5 CLIENT ARCHITECTURE                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: DATA INPUT                                        │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  Market Data     │         │  Server Signal   │         │
│  │  (MT5 Terminal)  │         │  (ZMQ Port 7778) │         │
│  └────────┬─────────┘         └────────┬─────────┘         │
│           │                            │                    │
│           │ OHLC, Tick                 │ TrendSignal        │
│           ▼                            ▼                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  LAYER 2: TREND DETECTION (Hybrid)                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────┐         │
│  │  Mode Switcher                                 │         │
│  │  ─────────────────────────────                 │         │
│  │  IF Server Connected:                          │         │
│  │     Use Server Signal (Kalman Filter)          │         │
│  │  ELSE:                                         │         │
│  │     Use Local HMA + Linear Regression          │         │
│  └────────────────────────────────────────────────┘         │
│           │                            │                    │
│           │                            │                    │
│     ┌─────▼──────┐              ┌─────▼──────┐            │
│     │  HMA +     │              │  Server    │            │
│     │  LinReg    │              │  Signal    │            │
│     │  (Local)   │              │  (Remote)  │            │
│     └─────┬──────┘              └─────┬──────┘            │
│           │                            │                    │
│           └────────────┬───────────────┘                    │
│                        │                                    │
│                        ▼                                    │
│              ┌──────────────────┐                          │
│              │  TrendSignal     │                          │
│              │  ───────────     │                          │
│              │  • Direction     │                          │
│              │  • Confidence    │                          │
│              │  • Market Bias   │                          │
│              └──────────────────┘                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  LAYER 3: STRATEGY LOGIC (Grid Integration)                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────┐         │
│  │  Grid Strategy Manager                         │         │
│  │  ──────────────────────                        │         │
│  │  Input: TrendSignal                            │         │
│  │  │                                             │         │
│  │  ├─ UpdateGridMode()                           │         │
│  │  │   • BIDIRECTIONAL (Sideways)               │         │
│  │  │   • BUY_ONLY (Uptrend)                     │         │
│  │  │   • SELL_ONLY (Downtrend)                  │         │
│  │  │                                             │         │
│  │  ├─ AdjustParameters()                         │         │
│  │  │   • Grid spacing                            │         │
│  │  │   • Lot sizes                               │         │
│  │  │   • Risk limits                             │         │
│  │  │                                             │         │
│  │  └─ ProcessGrid()                              │         │
│  │      • Entry logic                             │         │
│  │      • Exit logic                              │         │
│  │      • Position management                     │         │
│  └────────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  LAYER 4: RISK MANAGEMENT                                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐  ┌──────────────────┐                │
│  │  Magic Number   │  │  Risk Guardian   │                │
│  │  Manager        │  │                  │                │
│  │  ─────────────  │  │  ──────────────  │                │
│  │  • Strategy ID  │  │  • Max exposure  │                │
│  │  • Isolation    │  │  • Spread check  │                │
│  │  • Emergency    │  │  • Volatility    │                │
│  └─────────────────┘  └──────────────────┘                │
│                                                              │
│  ┌─────────────────────────────────────┐                   │
│  │  TransferToGrid() Emergency         │                   │
│  │  ──────────────────────────          │                   │
│  │  • Collect all orders               │                   │
│  │  • Transfer to Grid management      │                   │
│  │  • Recovery mode                    │                   │
│  └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  LAYER 5: ORDER EXECUTION                                   │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────┐                  │
│  │  MT5 Order Manager                   │                  │
│  │  ──────────────────                  │                  │
│  │  • OrderSend()                       │                  │
│  │  • OrderModify()                     │                  │
│  │  • OrderClose()                      │                  │
│  │  • Position tracking                 │                  │
│  └──────────────────────────────────────┘                  │
│                    │                                        │
│                    ▼                                        │
│           ┌─────────────────┐                              │
│           │  MT5 TERMINAL   │                              │
│           │  (Broker)       │                              │
│           └─────────────────┘                              │
└─────────────────────────────────────────────────────────────┘
```

---

<a name="hma-linreg"></a>
## 📊 **2. Component 1: HMA + Linear Regression**

### **2.1 Purpose**

HMA (Hull Moving Average) + Linear Regression เป็น **Standalone Trend Detector** สำหรับกรณีที่:
- Server ยังไม่เปิด
- Connection timeout
- Fallback mode

### **2.2 Algorithm**

```cpp
// ═══════════════════════════════════════════════════════
// HMA + LINEAR REGRESSION TREND DETECTOR
// ═══════════════════════════════════════════════════════

class CHMATrendDetector
{
private:
    // ─────────────────────────────────────────────────
    // Indicators
    // ─────────────────────────────────────────────────
    
    int m_hma_handle;           // HMA indicator handle
    double m_hma_buffer[];      // HMA values
    
    // ─────────────────────────────────────────────────
    // Parameters
    // ─────────────────────────────────────────────────
    
    int m_hma_period;           // HMA period (default: 21)
    int m_linreg_period;        // LinReg lookback (default: 20)
    double m_slope_threshold;   // Slope threshold (default: 0.001)
    double m_rsquared_threshold; // R² threshold (default: 0.7)
    
    // ─────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────
    
    ENUM_MARKET_BIAS m_current_bias;
    double m_current_direction;
    double m_current_confidence;
    datetime m_last_update;
    
public:
    
    // ═════════════════════════════════════════════════
    // Initialize
    // ═════════════════════════════════════════════════
    
    bool Initialize(string symbol, ENUM_TIMEFRAMES period)
    {
        // Set parameters
        m_hma_period = 21;
        m_linreg_period = 20;
        m_slope_threshold = 0.001;
        m_rsquared_threshold = 0.7;
        
        // Create HMA indicator
        m_hma_handle = iCustom(symbol, period, "HMA", m_hma_period);
        
        if(m_hma_handle == INVALID_HANDLE)
        {
            Print("❌ Failed to create HMA indicator");
            return false;
        }
        
        ArraySetAsSeries(m_hma_buffer, true);
        
        // Initialize state
        m_current_bias = MARKET_SIDEWAYS;
        m_current_direction = 0;
        m_current_confidence = 0;
        m_last_update = 0;
        
        Print("✅ HMA Trend Detector initialized");
        return true;
    }
    
    // ═════════════════════════════════════════════════
    // Calculate Trend Signal
    // ═════════════════════════════════════════════════
    
    TrendSignal Calculate()
    {
        TrendSignal signal;
        
        // ─────────────────────────────────────────────
        // Step 1: Copy HMA buffer
        // ─────────────────────────────────────────────
        
        int copied = CopyBuffer(m_hma_handle, 0, 0, m_linreg_period + 10, m_hma_buffer);
        
        if(copied < m_linreg_period)
        {
            Print("⚠️ Not enough HMA data");
            return GetDefaultSignal();
        }
        
        // ─────────────────────────────────────────────
        // Step 2: Extract recent HMA values
        // ─────────────────────────────────────────────
        
        double hma_values[];
        ArrayResize(hma_values, m_linreg_period);
        
        for(int i = 0; i < m_linreg_period; i++)
        {
            hma_values[i] = m_hma_buffer[i];
        }
        
        // ─────────────────────────────────────────────
        // Step 3: Calculate Linear Regression
        // ─────────────────────────────────────────────
        
        double slope = CalculateLinearRegressionSlope(hma_values);
        double rsquared = CalculateRSquared(hma_values, slope);
        
        // ─────────────────────────────────────────────
        // Step 4: Normalize slope to direction
        // ─────────────────────────────────────────────
        
        // Calculate ATR for normalization
        int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
        double atr_values[];
        ArrayResize(atr_values, 1);
        CopyBuffer(atr_handle, 0, 0, 1, atr_values);
        double atr = atr_values[0];
        
        IndicatorRelease(atr_handle);
        
        // Normalize slope
        double direction = 0;
        
        if(atr > 0)
        {
            // Scale slope by ATR
            direction = (slope / atr) * 100;
            
            // Clamp to -100 to +100
            direction = MathMax(-100, MathMin(100, direction));
        }
        
        // ─────────────────────────────────────────────
        // Step 5: Calculate confidence from R²
        // ─────────────────────────────────────────────
        
        double confidence = rsquared;  // R² is already 0-1
        
        // ─────────────────────────────────────────────
        // Step 6: Classify market bias
        // ─────────────────────────────────────────────
        
        ENUM_MARKET_BIAS bias = ClassifyMarketBias(direction, confidence);
        
        // ─────────────────────────────────────────────
        // Step 7: Build signal
        // ─────────────────────────────────────────────
        
        signal.bias = bias;
        signal.direction = direction;
        signal.confidence = confidence;
        signal.timestamp = TimeCurrent();
        signal.source = "HMA+LinReg";
        
        // Update state
        m_current_bias = bias;
        m_current_direction = direction;
        m_current_confidence = confidence;
        m_last_update = TimeCurrent();
        
        // Log
        Print(StringFormat("📊 HMA Trend: Direction=%.1f | R²=%.2f | Bias=%s",
              direction, rsquared, EnumToString(bias)));
        
        return signal;
    }
    
    // ═════════════════════════════════════════════════
    // Helper: Calculate Linear Regression Slope
    // ═════════════════════════════════════════════════
    
    double CalculateLinearRegressionSlope(double &values[])
    {
        int n = ArraySize(values);
        
        // Calculate means
        double sum_x = 0, sum_y = 0;
        for(int i = 0; i < n; i++)
        {
            sum_x += i;
            sum_y += values[i];
        }
        double mean_x = sum_x / n;
        double mean_y = sum_y / n;
        
        // Calculate slope
        double numerator = 0, denominator = 0;
        for(int i = 0; i < n; i++)
        {
            numerator += (i - mean_x) * (values[i] - mean_y);
            denominator += (i - mean_x) * (i - mean_x);
        }
        
        if(denominator == 0)
            return 0;
        
        return numerator / denominator;
    }
    
    // ═════════════════════════════════════════════════
    // Helper: Calculate R-Squared
    // ═════════════════════════════════════════════════
    
    double CalculateRSquared(double &values[], double slope)
    {
        int n = ArraySize(values);
        
        // Calculate means
        double sum_y = 0;
        for(int i = 0; i < n; i++)
            sum_y += values[i];
        double mean_y = sum_y / n;
        
        // Calculate intercept
        double intercept = mean_y - slope * (n - 1) / 2.0;
        
        // Calculate R²
        double ss_res = 0;  // Residual sum of squares
        double ss_tot = 0;  // Total sum of squares
        
        for(int i = 0; i < n; i++)
        {
            double y_pred = slope * i + intercept;
            ss_res += MathPow(values[i] - y_pred, 2);
            ss_tot += MathPow(values[i] - mean_y, 2);
        }
        
        if(ss_tot == 0)
            return 0;
        
        return 1.0 - (ss_res / ss_tot);
    }
    
    // ═════════════════════════════════════════════════
    // Helper: Classify Market Bias
    // ═════════════════════════════════════════════════
    
    ENUM_MARKET_BIAS ClassifyMarketBias(double direction, double confidence)
    {
        // Only classify if confidence is high enough
        if(confidence < m_rsquared_threshold)
            return MARKET_SIDEWAYS;  // Low confidence = sideways
        
        double abs_direction = MathAbs(direction);
        
        // Classify based on direction strength
        if(direction > 0)
        {
            if(abs_direction > 70)
                return MARKET_STRONG_UPTREND;
            else if(abs_direction > 40)
                return MARKET_MODERATE_UPTREND;
            else
                return MARKET_SIDEWAYS;
        }
        else
        {
            if(abs_direction > 70)
                return MARKET_STRONG_DOWNTREND;
            else if(abs_direction > 40)
                return MARKET_MODERATE_DOWNTREND;
            else
                return MARKET_SIDEWAYS;
        }
    }
    
    // ═════════════════════════════════════════════════
    // Get Default Signal (Error case)
    // ═════════════════════════════════════════════════
    
    TrendSignal GetDefaultSignal()
    {
        TrendSignal signal;
        signal.bias = MARKET_SIDEWAYS;
        signal.direction = 0;
        signal.confidence = 0;
        signal.timestamp = TimeCurrent();
        signal.source = "HMA+LinReg (Default)";
        return signal;
    }
};
```

### **2.3 HMA Calculation Details**

```
HMA Formula:
HMA(n) = WMA(2 * WMA(n/2) - WMA(n), sqrt(n))

Where:
  n = period (default 21)
  WMA = Weighted Moving Average

Steps:
1. Calculate WMA of period n/2
2. Calculate WMA of period n
3. Calculate: 2 * WMA(n/2) - WMA(n)
4. Apply WMA with period sqrt(n) to result

Example with n=21:
  WMA(10.5) → WMA(11)
  WMA(21)
  Difference = 2*WMA(11) - WMA(21)
  HMA(21) = WMA(4.58) → WMA(5) of difference
```

### **2.4 Linear Regression Details**

```
Linear Regression:
y = mx + b

Where:
  m = slope (trend direction)
  b = intercept
  x = time index (0, 1, 2, ...)
  y = HMA value

Slope calculation:
m = Σ((x - x̄)(y - ȳ)) / Σ((x - x̄)²)

R² calculation:
R² = 1 - (SS_res / SS_tot)

Where:
  SS_res = Σ(y - y_pred)²  (residual sum of squares)
  SS_tot = Σ(y - ȳ)²      (total sum of squares)
  
R² interpretation:
  0.0 - 0.3: Weak trend (ignore)
  0.3 - 0.7: Moderate trend (cautious)
  0.7 - 1.0: Strong trend (confident)
```

---

<a name="server-handler"></a>
## 🖥️ **3. Component 2: Server Signal Handler**

### **3.1 Purpose**

รับและประมวลผล Trend Signal จาก Python Server (Kalman Filter)

### **3.2 Implementation**

```cpp
// ═══════════════════════════════════════════════════════
// SERVER SIGNAL HANDLER
// ═══════════════════════════════════════════════════════

class CServerSignalHandler
{
private:
    // ─────────────────────────────────────────────────
    // ZMQ Socket
    // ─────────────────────────────────────────────────
    
    Context m_zmq_context;
    Socket m_zmq_sub;
    
    // ─────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────
    
    TrendSignal m_server_signal;
    bool m_is_connected;
    datetime m_last_received;
    double m_connection_timeout;  // Seconds
    
public:
    
    // ═════════════════════════════════════════════════
    // Initialize
    // ═════════════════════════════════════════════════
    
    bool Initialize(string symbol)
    {
        m_connection_timeout = 5.0;  // 5 seconds
        
        // Initialize ZMQ
        if(!m_zmq_context.initialize())
        {
            Print("❌ Failed to initialize ZMQ context");
            return false;
        }
        
        if(!m_zmq_sub.initialize(m_zmq_context, ZMQ_SUB))
        {
            Print("❌ Failed to initialize ZMQ subscriber");
            return false;
        }
        
        // Connect to server
        if(!m_zmq_sub.connect("tcp://127.0.0.1:7778"))
        {
            Print("❌ Failed to connect to server");
            return false;
        }
        
        // Subscribe to symbol
        m_zmq_sub.subscribe(symbol);
        
        // Initialize state
        m_is_connected = false;
        m_last_received = 0;
        
        m_server_signal.bias = MARKET_SIDEWAYS;
        m_server_signal.direction = 0;
        m_server_signal.confidence = 0;
        m_server_signal.timestamp = 0;
        m_server_signal.source = "Server (Kalman)";
        
        Print("✅ Server Signal Handler initialized");
        return true;
    }
    
    // ═════════════════════════════════════════════════
    // Poll for Server Signal
    // ═════════════════════════════════════════════════
    
    bool Poll()
    {
        string topic;
        uchar data[];
        
        // Non-blocking receive
        if(m_zmq_sub.recv(topic, data, true))
        {
            // Deserialize MessagePack
            TrendSignal signal = DeserializeSignal(data);
            
            // Update state
            m_server_signal = signal;
            m_is_connected = true;
            m_last_received = TimeCurrent();
            
            // Log
            Print(StringFormat("📥 Server: Direction=%.1f | Conf=%.2f | %s",
                  signal.direction, signal.confidence, EnumToString(signal.bias)));
            
            return true;
        }
        
        // Check timeout
        CheckConnectionTimeout();
        
        return false;
    }
    
    // ═════════════════════════════════════════════════
    // Check Connection Timeout
    // ═════════════════════════════════════════════════
    
    void CheckConnectionTimeout()
    {
        if(m_is_connected)
        {
            double elapsed = TimeCurrent() - m_last_received;
            
            if(elapsed > m_connection_timeout)
            {
                m_is_connected = false;
                Print("⚠️ Server connection timeout");
            }
        }
    }
    
    // ═════════════════════════════════════════════════
    // Get Server Signal
    // ═════════════════════════════════════════════════
    
    TrendSignal GetSignal()
    {
        return m_server_signal;
    }
    
    // ═════════════════════════════════════════════════
    // Is Connected?
    // ═════════════════════════════════════════════════
    
    bool IsConnected()
    {
        return m_is_connected;
    }
    
    // ═════════════════════════════════════════════════
    // Deserialize MessagePack Signal
    // ═════════════════════════════════════════════════
    
    TrendSignal DeserializeSignal(uchar &data[])
    {
        TrendSignal signal;
        
        // TODO: Implement MessagePack deserialization
        // For now, return default
        
        // Expected format:
        // {
        //     'type': 'TREND_SIGNAL',
        //     'symbol': 'EURUSD',
        //     'direction': +75.3,
        //     'confidence': 0.82,
        //     'strength': 'STRONG',
        //     'timestamp': 1703234567
        // }
        
        // Parse direction
        signal.direction = 0;  // Extract from data
        
        // Parse confidence
        signal.confidence = 0;  // Extract from data
        
        // Classify bias based on direction
        signal.bias = ClassifyFromDirection(signal.direction, signal.confidence);
        
        signal.timestamp = TimeCurrent();
        signal.source = "Server (Kalman)";
        
        return signal;
    }
    
    // ═════════════════════════════════════════════════
    // Classify Bias from Direction
    // ═════════════════════════════════════════════════
    
    ENUM_MARKET_BIAS ClassifyFromDirection(double direction, double confidence)
    {
        // Similar to HMA classifier
        if(confidence < 0.7)
            return MARKET_SIDEWAYS;
        
        double abs_dir = MathAbs(direction);
        
        if(direction > 0)
        {
            if(abs_dir > 70) return MARKET_STRONG_UPTREND;
            if(abs_dir > 40) return MARKET_MODERATE_UPTREND;
            return MARKET_SIDEWAYS;
        }
        else
        {
            if(abs_dir > 70) return MARKET_STRONG_DOWNTREND;
            if(abs_dir > 40) return MARKET_MODERATE_DOWNTREND;
            return MARKET_SIDEWAYS;
        }
    }
};
```

---

## ⏰ **I'll continue with the remaining components...**

ผมกำลังเขียนต่อครับ ยังมีอีก:
- Component 3: Grid Integration
- Component 4: Magic Number Management  
- Component 5: TransferToGrid Emergency
- Complete Logic Flow
- Parameters
- Testing Strategy
- Message Format

**ต้องการให้เขียนต่อทั้งหมดเลยไหมครับ?** หรือต้องการ review ส่วนที่เขียนไปแล้วก่อน?

รอคำสั่งครับ! 🎯
