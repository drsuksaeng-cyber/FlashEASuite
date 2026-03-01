//+------------------------------------------------------------------+
//| StrategyBase.mqh                                                 |
//| Base class for all trading strategies                           |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Base Strategy Class                                              |
//+------------------------------------------------------------------+
class CStrategyBase
{
protected:
    string            m_name;
    string            m_symbol;
    bool              m_initialized;
    bool              m_is_active;     // NEW: Strategy active flag
    double            m_weight;        // NEW: Strategy voting weight
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CStrategyBase()
    {
        m_name = "BaseStrategy";
        m_symbol = _Symbol;
        m_initialized = false;
        m_is_active = true;    // NEW: Active by default
        m_weight = 1.0;        // NEW: Default weight = 1.0
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    virtual ~CStrategyBase() {}
    
    //+------------------------------------------------------------------+
    //| Virtual methods to be overridden by derived classes             |
    //+------------------------------------------------------------------+
    virtual bool Init() { return true; }
    virtual void Deinit() {}
    virtual bool CheckEntry() { return false; }
    virtual bool CheckExit() { return false; }
    virtual void OnTick() {}
    virtual double GetScore() { return 0.0; }
    
    //+------------------------------------------------------------------+
    //| Get strategy name                                                |
    //+------------------------------------------------------------------+
    string GetName() const { return m_name; }
    
    //+------------------------------------------------------------------+
    //| Get symbol                                                       |
    //+------------------------------------------------------------------+
    string GetSymbol() const { return m_symbol; }
    
    //+------------------------------------------------------------------+
    //| Check if initialized                                             |
    //+------------------------------------------------------------------+
    bool IsInitialized() const { return m_initialized; }
    
    //+------------------------------------------------------------------+
    //| NEW: Activate/Deactivate Strategy                                |
    //+------------------------------------------------------------------+
    void Activate() { m_is_active = true; }
    void Deactivate() { m_is_active = false; }
    bool IsActive() const { return m_is_active; }
    
    //+------------------------------------------------------------------+
    //| NEW: Weight Management (for voting system)                       |
    //+------------------------------------------------------------------+
    double GetWeight() const { return m_weight; }
    void SetWeight(double weight) 
    { 
        if(weight >= 0.0 && weight <= 2.0)  // Limit: 0.0 - 2.0
            m_weight = weight; 
    }
};

//+------------------------------------------------------------------+
