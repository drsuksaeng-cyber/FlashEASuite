"""
Symbol Formatter - Broker-agnostic Symbol Handling
Handles prefix/suffix for different brokers
FlashEASuite V2 - Python Brain
"""
import json
import os

class SymbolFormatter:
    """Format symbols with broker-specific prefix/suffix"""
    
    def __init__(self, config_path="config.json"):
        """
        Initialize with config file
        
        Args:
            config_path: Path to config.json
        """
        self.prefix = ""
        self.suffix = ""
        
        # Load config if exists
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    config = json.load(f)
                    symbols_config = config.get('symbols', {})
                    self.prefix = symbols_config.get('prefix', '')
                    self.suffix = symbols_config.get('suffix', '')
                    
                print(f"📋 Symbol Formatting Loaded:")
                print(f"   Prefix: '{self.prefix}' {'' if self.prefix else '(none)'}")
                print(f"   Suffix: '{self.suffix}' {'' if self.suffix else '(none)'}")
                print(f"   Example: XAUUSD → {self.format_symbol('XAUUSD')}")
            except Exception as e:
                print(f"⚠️ Error loading config: {e}")
                print("   Using default (no prefix/suffix)")
        else:
            print(f"⚠️ Config not found: {config_path}")
            print("   Using default (no prefix/suffix)")
    
    def format_symbol(self, base_symbol: str) -> str:
        """
        Add prefix/suffix to base symbol
        
        Args:
            base_symbol: Clean symbol name (e.g., "XAUUSD")
            
        Returns:
            Formatted symbol (e.g., "XAUUSD.tp")
        """
        return f"{self.prefix}{base_symbol}{self.suffix}"
    
    def strip_symbol(self, formatted_symbol: str) -> str:
        """
        Remove prefix/suffix from formatted symbol
        
        Args:
            formatted_symbol: Formatted symbol (e.g., "XAUUSD.tp")
            
        Returns:
            Base symbol (e.g., "XAUUSD")
        """
        result = formatted_symbol
        
        # Remove prefix
        if self.prefix and result.startswith(self.prefix):
            result = result[len(self.prefix):]
        
        # Remove suffix
        if self.suffix and result.endswith(self.suffix):
            result = result[:-len(self.suffix)]
        
        return result
    
    def format_symbols(self, base_symbols: list) -> list:
        """Format multiple symbols"""
        return [self.format_symbol(s) for s in base_symbols]
    
    def strip_symbols(self, formatted_symbols: list) -> list:
        """Strip multiple symbols"""
        return [self.strip_symbol(s) for s in formatted_symbols]


# Global instance (singleton pattern)
_formatter = None

def get_formatter(config_path="config.json"):
    """Get global formatter instance"""
    global _formatter
    if _formatter is None:
        _formatter = SymbolFormatter(config_path)
    return _formatter


# Quick access functions
def format_symbol(base_symbol: str) -> str:
    """Quick format (uses global instance)"""
    return get_formatter().format_symbol(base_symbol)


def strip_symbol(formatted_symbol: str) -> str:
    """Quick strip (uses global instance)"""
    return get_formatter().strip_symbol(formatted_symbol)


if __name__ == "__main__":
    # Test cases
    print("\n" + "="*60)
    print("Symbol Formatter - Test Cases")
    print("="*60)
    
    # Test 1: No prefix/suffix (ICMarkets, OANDA)
    print("\n✅ Test 1: No prefix/suffix (ICMarkets)")
    formatter = SymbolFormatter()
    formatter.prefix = ""
    formatter.suffix = ""
    print(f"   Format 'XAUUSD': {formatter.format_symbol('XAUUSD')}")
    print(f"   Strip 'XAUUSD': {formatter.strip_symbol('XAUUSD')}")
    
    # Test 2: Suffix only (Test server)
    print("\n✅ Test 2: Suffix '.tp' (Test server)")
    formatter.suffix = ".tp"
    print(f"   Format 'XAUUSD': {formatter.format_symbol('XAUUSD')}")
    print(f"   Strip 'XAUUSD.tp': {formatter.strip_symbol('XAUUSD.tp')}")
    
    # Test 3: Suffix 'm' (Exness)
    print("\n✅ Test 3: Suffix 'm' (Exness)")
    formatter.suffix = "m"
    print(f"   Format 'XAUUSD': {formatter.format_symbol('XAUUSD')}")
    print(f"   Strip 'XAUUSDm': {formatter.strip_symbol('XAUUSDm')}")
    
    # Test 4: Prefix (FXPro)
    print("\n✅ Test 4: Prefix 'f' (FXPro)")
    formatter.prefix = "f"
    formatter.suffix = ""
    print(f"   Format 'XAUUSD': {formatter.format_symbol('XAUUSD')}")
    print(f"   Strip 'fXAUUSD': {formatter.strip_symbol('fXAUUSD')}")
    
    # Test 5: Both
    print("\n✅ Test 5: Prefix 'f' + Suffix '_i' (FXPro)")
    formatter.prefix = "f"
    formatter.suffix = "_i"
    print(f"   Format 'XAUUSD': {formatter.format_symbol('XAUUSD')}")
    print(f"   Strip 'fXAUUSD_i': {formatter.strip_symbol('fXAUUSD_i')}")
    
    print("\n" + "="*60)
    print("✅ All tests complete!")
    print("="*60)
