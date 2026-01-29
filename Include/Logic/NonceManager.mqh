//+------------------------------------------------------------------+
//|                                                 NonceManager.mqh |
//|                           FlashEASuite V2 - Security Component   |
//|                                  Anti-Replay Attack Protection   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Nonce Manager Class                                              |
//| Tracks used nonces to prevent replay attacks                    |
//+------------------------------------------------------------------+
class CNonceManager
{
private:
    string            m_used_nonces[1000];      // Array of used nonces
    datetime          m_nonce_timestamps[1000]; // Timestamp for each nonce
    int               m_nonce_count;            // Current nonce count
    int               m_cleanup_interval;       // Cleanup interval in seconds
    
public:
    //--- Constructor
    CNonceManager(int cleanup_interval = 3600);
    
    //--- Destructor
    ~CNonceManager();
    
    //--- Main methods
    bool IsNonceUsed(const string nonce);
    bool StoreNonce(const string nonce);
    void CleanupOldNonces();
    
    //--- Info methods
    int GetNonceCount() const { return m_nonce_count; }
    void Clear();
    void PrintStats();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CNonceManager::CNonceManager(int cleanup_interval = 3600)
{
    m_nonce_count = 0;
    m_cleanup_interval = cleanup_interval;
    ArrayInitialize(m_used_nonces, "");
    ArrayInitialize(m_nonce_timestamps, 0);
    
    Print("✅ NonceManager initialized");
    Print("   Max nonces: 1000");
    Print("   Cleanup interval: ", m_cleanup_interval, " seconds");
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CNonceManager::~CNonceManager()
{
    // Cleanup
}

//+------------------------------------------------------------------+
//| Check if nonce has been used                                    |
//+------------------------------------------------------------------+
bool CNonceManager::IsNonceUsed(const string nonce)
{
    // Auto cleanup old nonces
    CleanupOldNonces();
    
    // Search for nonce
    for(int i = 0; i < m_nonce_count; i++)
    {
        if(m_used_nonces[i] == nonce)
        {
            Print("⚠️ SECURITY ALERT: Nonce already used!");
            Print("   Nonce: ", StringSubstr(nonce, 0, 16), "...");
            Print("   This is a REPLAY ATTACK attempt!");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Store a nonce as used                                           |
//+------------------------------------------------------------------+
bool CNonceManager::StoreNonce(const string nonce)
{
    // Check if already used
    if(IsNonceUsed(nonce))
    {
        return false;
    }
    
    // Check if array is full
    if(m_nonce_count >= 1000)
    {
        // Try cleanup first
        CleanupOldNonces();
        
        // Still full?
        if(m_nonce_count >= 1000)
        {
            Print("⚠️ WARNING: Nonce storage full!");
            Print("   Cannot store more nonces until cleanup");
            return false;
        }
    }
    
    // Store nonce
    m_used_nonces[m_nonce_count] = nonce;
    m_nonce_timestamps[m_nonce_count] = TimeCurrent();
    m_nonce_count++;
    
    return true;
}

//+------------------------------------------------------------------+
//| Cleanup old nonces (older than cleanup_interval)                |
//+------------------------------------------------------------------+
void CNonceManager::CleanupOldNonces()
{
    datetime cutoff = TimeCurrent() - m_cleanup_interval;
    int initial_count = m_nonce_count;
    
    // Compact array (remove expired nonces)
    int write_index = 0;
    for(int i = 0; i < m_nonce_count; i++)
    {
        if(m_nonce_timestamps[i] > cutoff)
        {
            // Keep this nonce (still valid)
            if(write_index != i)
            {
                m_used_nonces[write_index] = m_used_nonces[i];
                m_nonce_timestamps[write_index] = m_nonce_timestamps[i];
            }
            write_index++;
        }
    }
    
    // Update count
    m_nonce_count = write_index;
    
    // Log cleanup
    int removed = initial_count - m_nonce_count;
    if(removed > 0)
    {
        Print("🧹 Cleaned up ", removed, " expired nonces");
        Print("   Active nonces: ", m_nonce_count);
    }
}

//+------------------------------------------------------------------+
//| Clear all nonces (emergency/testing)                            |
//+------------------------------------------------------------------+
void CNonceManager::Clear()
{
    ArrayInitialize(m_used_nonces, "");
    ArrayInitialize(m_nonce_timestamps, 0);
    m_nonce_count = 0;
    
    Print("⚠️ All nonces cleared");
}

//+------------------------------------------------------------------+
//| Print statistics                                                |
//+------------------------------------------------------------------+
void CNonceManager::PrintStats()
{
    Print("📊 Nonce Manager Statistics:");
    Print("   Total nonces: ", m_nonce_count);
    Print("   Max capacity: 1000");
    Print("   Usage: ", (m_nonce_count * 100.0 / 1000.0), "%");
    
    if(m_nonce_count > 0)
    {
        // Find oldest and newest
        datetime oldest = m_nonce_timestamps[0];
        datetime newest = m_nonce_timestamps[0];
        
        for(int i = 1; i < m_nonce_count; i++)
        {
            if(m_nonce_timestamps[i] < oldest)
                oldest = m_nonce_timestamps[i];
            if(m_nonce_timestamps[i] > newest)
                newest = m_nonce_timestamps[i];
        }
        
        Print("   Oldest nonce age: ", (TimeCurrent() - oldest), " seconds");
        Print("   Newest nonce age: ", (TimeCurrent() - newest), " seconds");
    }
}

//+------------------------------------------------------------------+
