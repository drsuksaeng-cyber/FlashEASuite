//+------------------------------------------------------------------+
//|                                              SequenceTracker.mqh |
//|                           FlashEASuite V2 - Security Component   |
//|                                    Policy Ordering Validation    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Symbol Sequence Structure                                        |
//+------------------------------------------------------------------+
struct SymbolSequence
{
    string   symbol;         // Symbol name
    long     last_sequence;  // Last valid sequence number
};

//+------------------------------------------------------------------+
//| Sequence Tracker Class                                           |
//| Tracks policy sequence numbers per symbol                        |
//+------------------------------------------------------------------+
class CSequenceTracker
{
private:
    SymbolSequence    m_sequences[50];      // Track up to 50 symbols
    int               m_sequence_count;     // Current number of tracked symbols
    string            m_storage_file;       // File for persistence
    
public:
    //--- Constructor
    CSequenceTracker(string storage_file = "policy_sequences.csv");
    
    //--- Destructor
    ~CSequenceTracker();
    
    //--- Main methods
    bool ValidateSequence(const string symbol, long sequence);
    void UpdateSequence(const string symbol, long sequence);
    long GetLastSequence(const string symbol);
    
    //--- Persistence
    void SaveToFile();
    void LoadFromFile();
    
    //--- Info methods
    int GetSymbolCount() const { return m_sequence_count; }
    void PrintStats();
    void ResetSymbol(const string symbol);
    void ResetAll();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSequenceTracker::CSequenceTracker(string storage_file = "policy_sequences.csv")
{
    m_sequence_count = 0;
    m_storage_file = storage_file;
    
    // Initialize arrays
    for(int i = 0; i < 50; i++)
    {
        m_sequences[i].symbol = "";
        m_sequences[i].last_sequence = 0;
    }
    
    // Load existing sequences
    LoadFromFile();
    
    Print("✅ SequenceTracker initialized");
    Print("   Storage file: ", m_storage_file);
    Print("   Tracked symbols: ", m_sequence_count);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSequenceTracker::~CSequenceTracker()
{
    // Save before destruction
    SaveToFile();
}

//+------------------------------------------------------------------+
//| Validate sequence number (must be > last_sequence)              |
//+------------------------------------------------------------------+
bool CSequenceTracker::ValidateSequence(const string symbol, long sequence)
{
    long last_seq = GetLastSequence(symbol);
    
    // First policy for this symbol (sequence 1 expected)
    if(last_seq == 0)
    {
        if(sequence == 1)
        {
            return true;
        }
        else
        {
            Print("❌ SECURITY ALERT: Invalid first sequence!");
            Print("   Symbol: ", symbol);
            Print("   Expected: 1");
            Print("   Received: ", sequence);
            return false;
        }
    }
    
    // Sequence must increment
    if(sequence > last_seq)
    {
        return true;
    }
    else
    {
        Print("❌ SECURITY ALERT: Out-of-order sequence!");
        Print("   Symbol: ", symbol);
        Print("   Last sequence: ", last_seq);
        Print("   New sequence: ", sequence);
        Print("   This policy is OLD or REPLAYED!");
        return false;
    }
}

//+------------------------------------------------------------------+
//| Update last sequence number for a symbol                        |
//+------------------------------------------------------------------+
void CSequenceTracker::UpdateSequence(const string symbol, long sequence)
{
    // Find existing entry
    for(int i = 0; i < m_sequence_count; i++)
    {
        if(m_sequences[i].symbol == symbol)
        {
            m_sequences[i].last_sequence = sequence;
            SaveToFile();
            Print("✅ Sequence updated: ", symbol, " → ", sequence);
            return;
        }
    }
    
    // New symbol
    if(m_sequence_count < 50)
    {
        m_sequences[m_sequence_count].symbol = symbol;
        m_sequences[m_sequence_count].last_sequence = sequence;
        m_sequence_count++;
        SaveToFile();
        Print("✅ New symbol tracked: ", symbol, " (seq: ", sequence, ")");
    }
    else
    {
        Print("⚠️ WARNING: Symbol limit reached (50)");
        Print("   Cannot track: ", symbol);
    }
}

//+------------------------------------------------------------------+
//| Get last sequence number for a symbol                           |
//+------------------------------------------------------------------+
long CSequenceTracker::GetLastSequence(const string symbol)
{
    for(int i = 0; i < m_sequence_count; i++)
    {
        if(m_sequences[i].symbol == symbol)
        {
            return m_sequences[i].last_sequence;
        }
    }
    
    // Symbol not found (new symbol)
    return 0;
}

//+------------------------------------------------------------------+
//| Save sequences to file                                          |
//+------------------------------------------------------------------+
void CSequenceTracker::SaveToFile()
{
    int handle = FileOpen(m_storage_file, FILE_WRITE|FILE_TXT);
    
    if(handle == INVALID_HANDLE)
    {
        Print("⚠️ Failed to save sequences: ", GetLastError());
        return;
    }
    
    // Write header
    FileWriteString(handle, "symbol,sequence\n");
    
    // Write data
    for(int i = 0; i < m_sequence_count; i++)
    {
        string line = m_sequences[i].symbol + "," + 
                     IntegerToString(m_sequences[i].last_sequence) + "\n";
        FileWriteString(handle, line);
    }
    
    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Load sequences from file                                         |
//+------------------------------------------------------------------+
void CSequenceTracker::LoadFromFile()
{
    int handle = FileOpen(m_storage_file, FILE_READ|FILE_TXT);
    
    if(handle == INVALID_HANDLE)
    {
        Print("   No existing sequence file (will create new)");
        return;
    }
    
    // Skip header
    if(!FileIsEnding(handle))
        FileReadString(handle);
    
    // Read data
    m_sequence_count = 0;
    while(!FileIsEnding(handle) && m_sequence_count < 50)
    {
        string line = FileReadString(handle);
        
        if(StringLen(line) > 0)
        {
            string parts[];
            int count = StringSplit(line, ',', parts);
            
            if(count == 2)
            {
                m_sequences[m_sequence_count].symbol = parts[0];
                m_sequences[m_sequence_count].last_sequence = StringToInteger(parts[1]);
                m_sequence_count++;
            }
        }
    }
    
    FileClose(handle);
    Print("   Loaded ", m_sequence_count, " sequences from file");
}

//+------------------------------------------------------------------+
//| Print statistics                                                |
//+------------------------------------------------------------------+
void CSequenceTracker::PrintStats()
{
    Print("📊 Sequence Tracker Statistics:");
    Print("   Tracked symbols: ", m_sequence_count);
    Print("   Max capacity: 50");
    
    if(m_sequence_count > 0)
    {
        Print("   Symbol details:");
        for(int i = 0; i < m_sequence_count; i++)
        {
            Print("     ", m_sequences[i].symbol, ": ", 
                  m_sequences[i].last_sequence);
        }
    }
}

//+------------------------------------------------------------------+
//| Reset sequence for a specific symbol                            |
//+------------------------------------------------------------------+
void CSequenceTracker::ResetSymbol(const string symbol)
{
    for(int i = 0; i < m_sequence_count; i++)
    {
        if(m_sequences[i].symbol == symbol)
        {
            // Remove by shifting
            for(int j = i; j < m_sequence_count - 1; j++)
            {
                m_sequences[j] = m_sequences[j + 1];
            }
            
            m_sequence_count--;
            SaveToFile();
            Print("⚠️ Reset sequence for: ", symbol);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Reset all sequences                                             |
//+------------------------------------------------------------------+
void CSequenceTracker::ResetAll()
{
    for(int i = 0; i < 50; i++)
    {
        m_sequences[i].symbol = "";
        m_sequences[i].last_sequence = 0;
    }
    
    m_sequence_count = 0;
    SaveToFile();
    
    Print("⚠️ All sequences reset");
}

//+------------------------------------------------------------------+
