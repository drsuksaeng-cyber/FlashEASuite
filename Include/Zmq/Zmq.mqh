//+------------------------------------------------------------------+
//|                                                          Zmq.mqh |
//|                                       CORRECTED: Fixed setSubscribe() |
//+------------------------------------------------------------------+
#property strict
#define ZMQ_PUB 1
#define ZMQ_SUB 2
#define ZMQ_PUSH 8
#define ZMQ_PULL 7
#define ZMQ_LINGER 17
#define ZMQ_SNDHWM 23
#define ZMQ_SUBSCRIBE 6      // ✅ ADDED: For subscription

#import "libzmq.dll"
   long zmq_ctx_new();
   int  zmq_ctx_term(long context);
   long zmq_socket(long context, int type);
   int  zmq_close(long socket);
   int  zmq_connect(long socket, uchar &addr[]);
   int  zmq_bind(long socket, uchar &addr[]);
   int  zmq_send(long socket, uchar &data[], int size, int flags);
   int  zmq_recv(long socket, uchar &data[], int size, int flags);
   int  zmq_setsockopt(long socket, int option_name, int &option_value, int option_len);
   int  zmq_setsockopt(long socket, int option_name, uchar &option_value[], int option_len);  // ✅ ADDED: Overload for uchar[]
#import

class Context {
   long m_context;
public:
   Context() { m_context = zmq_ctx_new(); }
   ~Context() { if(m_context>0) zmq_ctx_term(m_context); }
   bool initialize() { if(m_context<=0) m_context=zmq_ctx_new(); return (m_context>0); }
   long get() { return m_context; }
   void shutdown() { if(m_context>0) { zmq_ctx_term(m_context); m_context=0; } }
};

class Socket {
   long m_socket;
public:
   Socket(int type) { m_socket=0; }
   Socket(Context &ctx, int type) { m_socket = zmq_socket(ctx.get(), type); }
   ~Socket() { close(); }
   
   bool initialize(Context &ctx, int type) {
      m_socket = zmq_socket(ctx.get(), type);
      return (m_socket > 0);
   }
   
   void close() { if(m_socket>0) { zmq_close(m_socket); m_socket=0; } }
   
   bool connect(string address) {
      uchar addr[]; StringToCharArray(address, addr);
      return (zmq_connect(m_socket, addr) == 0);
   }
   
   bool bind(string address) {
      uchar addr[]; StringToCharArray(address, addr);
      return (zmq_bind(m_socket, addr) == 0);
   }

   void setLinger(int linger) {
      if(m_socket<=0) return;
      zmq_setsockopt(m_socket, ZMQ_LINGER, linger, 4);
   }
   
   void setSendHighWaterMark(int hwm) {
      if(m_socket<=0) return;
      zmq_setsockopt(m_socket, ZMQ_SNDHWM, hwm, 4);
   }

   // ✅ CORRECTED: setSubscribe() method for SUB sockets
   // CRITICAL FIX: StringToCharArray("", t) creates t=[0] (size=1 with null terminator)
   // but ZMQ needs empty array (size=0) to subscribe to ALL messages
   void setSubscribe(string topic="") {
      if(m_socket<=0) return;
      
      if(topic == "") {
         // Subscribe to ALL messages (no topic filter)
         // MUST use empty array with size=0, NOT [0] with size=1!
         uchar empty[];
         ArrayResize(empty, 0);  // Create empty array (size=0)
         zmq_setsockopt(m_socket, ZMQ_SUBSCRIBE, empty, 0);
      } else {
         // Subscribe to specific topic
         uchar t[];
         StringToCharArray(topic, t);
         // StringToCharArray adds null terminator, we must remove it!
         // Example: "ABC" → t = [65, 66, 67, 0] (size=4)
         // We want: [65, 66, 67] (size=3)
         ArrayResize(t, ArraySize(t) - 1);  // Remove null terminator
         zmq_setsockopt(m_socket, ZMQ_SUBSCRIBE, t, ArraySize(t));
      }
   }

   int send_bin(uchar &data[], bool nowait=true) {
      if(m_socket<=0) return -1;
      int flags = nowait ? 1 : 0;
      return zmq_send(m_socket, data, ArraySize(data), flags);
   }
   
   int recv_bin(uchar &data[], int size, bool nowait) {
      if(m_socket<=0) return -1;
      ArrayResize(data, size);
      int flags = nowait ? 1 : 0;
      return zmq_recv(m_socket, data, size, flags);
   }
};
