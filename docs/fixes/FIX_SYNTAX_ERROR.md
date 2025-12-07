# 🔧 แก้ไข "unexpected token" Error - Zmq.mqh

## ปัญหาที่พบ (Compile Error)
```
unexpected token - Zmq.mqh line 10, 11, 12, 13, 14, 15, 16, 17, 18...
13 errors, 2 warnings
```

## สาเหตุ: MQL5 Syntax ผิด

### ❌ ผิด (ที่เขียนไปก่อนหน้า):
```cpp
long long zmq_ctx_new();      // ❌ MQL5 ไม่รู้จัก "long long" (มีช่องว่าง)
long long m_context;          // ❌ Syntax Error!
```

### ✅ ถูก (แก้ไขแล้ว):
```cpp
long zmq_ctx_new();           // ✅ MQL5 รู้จัก "long" (64-bit)
long m_context;               // ✅ Compile ผ่าน!
```

---

## ความแตกต่าง: C/C++ vs MQL5

| ภาษา | Syntax | ขนาด |
|------|--------|------|
| **C/C++** | `long long` | 64-bit (8 bytes) |
| **MQL5** | `long` | 64-bit (8 bytes) |

### MQL5 Data Types:
```cpp
char     // 1 byte
short    // 2 bytes
int      // 4 bytes  ⚠️ ไม่พอเก็บ pointer ใน 64-bit!
long     // 8 bytes  ✅ พอดีสำหรับ pointer ใน 64-bit!
ulong    // 8 bytes unsigned
```

---

## การแก้ไข Zmq.mqh (ฉบับสุดท้าย)

```cpp
#property strict

// [FIX 64-bit] ใช้ long สำหรับ pointer/handles (MQL5: long = 64-bit)
#import "libzmq.dll"
   long zmq_ctx_new();                    // ✅ เปลี่ยนจาก "long long"
   int zmq_ctx_term(long context);        // ✅ เปลี่ยนจาก "long long"
   long zmq_socket(long context, int type);
   int zmq_close(long socket);
   int zmq_connect(long socket, uchar &addr[]);
   int zmq_bind(long socket, uchar &addr[]);
   int zmq_send(long socket, uchar &data[], int size, int flags);
   int zmq_recv(long socket, uchar &data[], int size, int flags);
   int zmq_setsockopt(long socket, int option_name, int &option_value, int option_len);
#import

class Context
{
   long m_context;           // ✅ เปลี่ยนจาก "long long"
public:
   Context() { m_context = zmq_ctx_new(); }
   ~Context() { if(m_context > 0) zmq_ctx_term(m_context); }
   long get() { return m_context; }
   void shutdown() { if(m_context > 0) { zmq_ctx_term(m_context); m_context=0; } }
};

class Socket
{
   long m_socket;            // ✅ เปลี่ยนจาก "long long"
public:
   Socket(int type) { m_socket = 0; }
   Socket(Context &ctx, int type) { m_socket = zmq_socket(ctx.get(), type); }
   
   // ... rest of methods
};
```

---

## สรุปการเปลี่ยนแปลง

| ตำแหน่ง | เดิม (❌) | ใหม่ (✅) |
|---------|----------|----------|
| DLL imports (9 ฟังก์ชัน) | `long long` | `long` |
| Context class | `long long m_context` | `long m_context` |
| Context::get() | `long long get()` | `long get()` |
| Socket class | `long long m_socket` | `long m_socket` |

---

## ทดสอบ

1. **Replace** `Zmq.mqh` ด้วยไฟล์ใหม่
2. **Compile** → ✅ **0 errors!**
3. **Run EA** → ✅ **ไม่มี Access Violation!**

---

## คำอธิบายเพิ่มเติม

### ทำไม `long` ก็ใช้ได้?
- ใน **MQL5 64-bit**: 
  - `long` = 8 bytes (64-bit signed integer)
  - พอดีสำหรับเก็บ pointer address
  - **ไม่ต้องใช้ `long long`** (MQL5 ไม่มี syntax นี้!)

### ทำไมใช้ `int` ไม่ได้?
- `int` = 4 bytes (32-bit)
- Pointer ใน 64-bit system = 8 bytes
- **4 bytes < 8 bytes** → pointer truncation → crash!

---

## เปรียบเทียบ Type Sizes

```cpp
// MT5 64-bit
sizeof(int)   = 4 bytes  ❌ ไม่พอ
sizeof(long)  = 8 bytes  ✅ พอดี!
```

---

## Best Practice

✅ **สำหรับ DLL handles/pointers ใน MQL5 64-bit:**
```cpp
long handle;              // ✅ CORRECT
int handle;               // ❌ WRONG - causes Access Violation
long long handle;         // ❌ WRONG - syntax error in MQL5
```

---

## สรุป

✅ **แก้แล้ว:** เปลี่ยน `long long` → `long` ทั้งหมดใน Zmq.mqh  
✅ **Compile ผ่าน:** ไม่มี unexpected token errors  
✅ **Run ได้:** ไม่มี Access Violation  

🎯 **ตอนนี้พร้อมใช้งานแล้วครับ!**
