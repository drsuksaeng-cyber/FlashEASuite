//+------------------------------------------------------------------+
//|                                                       ZmqHub.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                                    ZMQ Connection Manager        |
//+------------------------------------------------------------------+
#property strict
#include "Zmq.mqh"

// CRITICAL: Zmq.mqh defines "Context" and "Socket", not "CZmqContext"!
#define CZmqContext Context
#define CZmqSocket  Socket

class CZmqHub
  {
private:
   CZmqContext* m_context;
   CZmqSocket* m_sub_socket;
   CZmqSocket* m_push_socket;
   bool              m_connected;

public:
   CZmqHub() 
     { 
      m_context = NULL; 
      m_sub_socket = NULL; 
      m_push_socket = NULL; 
      m_connected = false; 
     }
     
   ~CZmqHub() 
     { 
      Shutdown(); 
     }

   bool Initialize(int recv_timeout=1000, int send_timeout=1000)
     {
      if(m_context == NULL) 
         m_context = new CZmqContext();
      return (m_context != NULL);
     }

   bool Subscribe(string address, string topic="")
     {
      if(m_context == NULL) return false;
      
      m_sub_socket = new CZmqSocket(*m_context, 2); 
      m_sub_socket.setLinger(0);
      
      if(!m_sub_socket.connect(address)) return false;
      
      // CRITICAL FIX: Must subscribe to topic to receive messages!
      m_sub_socket.setSubscribe(topic);
      
      m_connected = true;
      return true;
     }

   bool ConnectPush(string address)
     {
      if(m_context == NULL) return false;
      
      m_push_socket = new CZmqSocket(*m_context, 8);
      m_push_socket.setLinger(0);
      
      return m_push_socket.connect(address);
     }

   // Receive data from SUB socket
   bool Poll(uchar &out_data[])
     {
      if(m_sub_socket == NULL) return false;
      
      uchar buffer[];
      int size = 4096; // 4KB Buffer
      
      // Use recv_bin from Zmq.mqh
      int rc = m_sub_socket.recv_bin(buffer, size, true); 
      
      if(rc > 0)
        {
         ArrayResize(out_data, rc);
         ArrayCopy(out_data, buffer, 0, 0, rc);
         return true;
        }
      return false;
     }

   void Shutdown()
     {
      if(m_sub_socket != NULL) 
        { 
         m_sub_socket.close(); 
         delete m_sub_socket; 
         m_sub_socket = NULL; 
        }
        
      if(m_push_socket != NULL) 
        { 
         m_push_socket.close(); 
         delete m_push_socket; 
         m_push_socket = NULL; 
        }
        
      if(m_context != NULL) 
        { 
         m_context.shutdown(); 
         delete m_context; 
         m_context = NULL; 
        }
        
      m_connected = false;
     }
  };
//+------------------------------------------------------------------+
