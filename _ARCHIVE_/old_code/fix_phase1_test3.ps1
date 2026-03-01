# Quick Fix Script for Phase 1 Test 3
# This adds the missing analyze_market_condition function to analysis.py

$analysisPath = "core\strategy\analysis.py"

# Check if file exists
if (-not (Test-Path $analysisPath)) {
    Write-Host "❌ Error: analysis.py not found at $analysisPath"
    Write-Host "Current directory: $(Get-Location)"
    exit 1
}

# Backup original
Copy-Item $analysisPath "$analysisPath.backup" -Force
Write-Host "✅ Backed up analysis.py to analysis.py.backup"

# Function to add
$functionToAdd = @'


def analyze_market_condition(tick_data, price_history=None, **kwargs):
    """
    Analyze market condition from tick data (for Spike integration).
    """
    symbol = tick_data.get('symbol', 'UNKNOWN')
    bid = tick_data.get('bid', 0.0)
    ask = tick_data.get('ask', 0.0)
    
    spread = ask - bid
    spread_pct = (spread / bid * 100) if bid > 0 else 0
    
    trend = 'NEUTRAL'
    volatility = 0.0
    confidence = 0.5
    
    if price_history and len(price_history) >= 10:
        recent_prices = price_history[-10:]
        sma = sum(recent_prices) / len(recent_prices)
        current_price = (bid + ask) / 2
        
        if current_price > sma * 1.001:
            trend = 'BUY'
            confidence = 0.6
        elif current_price < sma * 0.999:
            trend = 'SELL'
            confidence = 0.6
        
        if len(recent_prices) >= 2:
            mean = sum(recent_prices) / len(recent_prices)
            variance = sum((x - mean) ** 2 for x in recent_prices) / len(recent_prices)
            volatility = variance ** 0.5
    
    return {
        'symbol': symbol,
        'price': (bid + ask) / 2,
        'bid': bid,
        'ask': ask,
        'spread': spread,
        'spread_pct': spread_pct,
        'trend': trend,
        'volatility': volatility,
        'confidence': confidence,
        'timestamp': tick_data.get('timestamp', 0)
    }
'@

# Check if function already exists
$content = Get-Content $analysisPath -Raw
if ($content -match "def analyze_market_condition") {
    Write-Host "✅ Function already exists, skipping..."
} else {
    # Add function to end of file
    Add-Content -Path $analysisPath -Value $functionToAdd
    Write-Host "✅ Added analyze_market_condition function"
}

# Test import
Write-Host "`nTesting import..."
python -c "from core.strategy.policy import generate_spike_policy; print('✅ Policy OK')" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ SUCCESS! Phase 1 Test 3 fixed!"
} else {
    Write-Host "`n❌ Still has errors. Restoring backup..."
    Copy-Item "$analysisPath.backup" $analysisPath -Force
    Write-Host "Restored original analysis.py"
}
