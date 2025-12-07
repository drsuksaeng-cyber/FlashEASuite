//+------------------------------------------------------------------+
//|                                                   MqlMsgPack.mqh |
//|                        FlashEASuite V2 - MessagePack Serializer  |
//|                                      Binary Protocol Implementation |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property strict

class CMsgPack
{
private:
   uchar m_buffer[];
   int   m_position;
   int   m_capacity;
   
   void Reserve(int additionalSize)
   {
      int requiredSize = m_position + additionalSize;
      if(requiredSize > m_capacity)
      {
         int newCapacity = MathMax(m_capacity * 2, requiredSize + 128);
         ArrayResize(m_buffer, newCapacity, newCapacity * 2);
         m_capacity = newCapacity;
      }
   }
   
   void WriteByte(uchar byte) { Reserve(1); m_buffer[m_position++] = byte; }
   
   void WriteBytes(const uchar &data[], int size)
   {
      Reserve(size);
      for(int i = 0; i < size; i++) m_buffer[m_position++] = data[i];
   }
   
   void LongToBytes(long value, uchar &bytes[], int numBytes)
   {
      ArrayResize(bytes, numBytes);
      for(int i = 0; i < numBytes; i++)
         bytes[i] = (uchar)((value >> (8 * (numBytes - 1 - i))) & 0xFF);
   }
   
   // --- ส่วนที่แก้ไข (Fixed Warning) ---
   void DoubleToBytes(double value, uchar &bytes[])
   {
      ArrayResize(bytes, 8);
      ulong bits = 0; // แก้จาก long เป็น ulong
      
      if(value == 0.0) { bits = (1.0/value < 0) ? 0x8000000000000000 : 0; }
      else if(value != value) { bits = 0x7FF8000000000000; }
      else {
         int sign = (value < 0) ? 1 : 0;
         double absVal = MathAbs(value);
         int exponent = 0;
         double mantissa = absVal;
         if(mantissa >= 2.0) { while(mantissa >= 2.0) { mantissa /= 2.0; exponent++; } }
         else if(mantissa < 1.0 && mantissa > 0.0) { while(mantissa < 1.0) { mantissa *= 2.0; exponent--; } }
         exponent += 1023;
         mantissa -= 1.0;
         long fraction = (long)(mantissa * MathPow(2, 52));
         
         // เพิ่ม (ulong) cast เพื่อความชัดเจน
         bits = ((ulong)sign << 63) | ((ulong)exponent << 52) | ((ulong)fraction & 0xFFFFFFFFFFFFF);
      }
      for(int i = 0; i < 8; i++) bytes[i] = (uchar)((bits >> (8 * (7 - i))) & 0xFF);
   }
   // ----------------------------------

public:
   CMsgPack() { m_position = 0; m_capacity = 256; ArrayResize(m_buffer, m_capacity, 512); }
   void Reset() { m_position = 0; }
   void GetData(uchar &output[]) { ArrayResize(output, m_position); ArrayCopy(output, m_buffer, 0, 0, m_position); }
   int GetSize() { return m_position; }
   
   void PackArray(int size) {
      if(size <= 15) WriteByte((uchar)(0x90 | size));
      else if(size <= 65535) { WriteByte(0xdc); WriteByte((uchar)((size >> 8) & 0xFF)); WriteByte((uchar)(size & 0xFF)); }
      else { WriteByte(0xdd); uchar bytes[]; LongToBytes(size, bytes, 4); WriteBytes(bytes, 4); }
   }
   
   void PackInt(long value) {
      if(value >= 0) {
         if(value <= 127) WriteByte((uchar)value);
         else if(value <= 255) { WriteByte(0xcc); WriteByte((uchar)value); }
         else if(value <= 65535) { WriteByte(0xcd); WriteByte((uchar)((value >> 8) & 0xFF)); WriteByte((uchar)(value & 0xFF)); }
         else { WriteByte(0xcf); uchar bytes[]; LongToBytes(value, bytes, 8); WriteBytes(bytes, 8); }
      } else {
         if(value >= -32) WriteByte((uchar)(0xe0 | (value & 0x1f)));
         else if(value >= -128) { WriteByte(0xd0); WriteByte((uchar)value); }
         else if(value >= -32768) { WriteByte(0xd1); WriteByte((uchar)((value >> 8) & 0xFF)); WriteByte((uchar)(value & 0xFF)); }
         else { WriteByte(0xd3); uchar bytes[]; LongToBytes(value, bytes, 8); WriteBytes(bytes, 8); }
      }
   }
   
   void PackDouble(double value) { WriteByte(0xcb); uchar bytes[]; DoubleToBytes(value, bytes); WriteBytes(bytes, 8); }
   
   void PackString(string value) {
      uchar strBytes[];
      int strLen = StringToCharArray(value, strBytes, 0, WHOLE_ARRAY, CP_UTF8) - 1;
      if(strLen < 0) strLen = 0;
      if(strLen <= 31) WriteByte((uchar)(0xa0 | strLen));
      else if(strLen <= 255) { WriteByte(0xd9); WriteByte((uchar)strLen); }
      else { WriteByte(0xda); WriteByte((uchar)((strLen >> 8) & 0xFF)); WriteByte((uchar)(strLen & 0xFF)); }
      if(strLen > 0) WriteBytes(strBytes, strLen);
   }
};