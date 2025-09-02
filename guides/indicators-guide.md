# Complete Indicators Guide

This comprehensive guide covers all indicators available in the TradingIndicators library, including their mathematical foundations, use cases, and practical examples.

## Trend Indicators

Trend indicators help identify the direction and strength of price movements over time.

### Simple Moving Average (SMA)

**Purpose**: Smooths price data to identify trend direction by averaging prices over a specific period.

**Formula**: SMA = (P₁ + P₂ + ... + Pₙ) / n

**Parameters**:
- `prices`: List of decimal prices
- `period`: Number of periods to average (typically 10, 20, 50, 200)

**Example**:
```elixir
prices = [100, 101, 102, 103, 104, 105] |> Enum.map(&Decimal.new/1)
sma_3 = TradingIndicators.Trend.SMA.calculate(prices, 3)
# Result: [101.0, 102.0, 103.0, 104.0] (4 values for 6 input prices)
```

**Interpretation**:
- Price above SMA: Uptrend
- Price below SMA: Downtrend
- SMA slope indicates trend strength

### Exponential Moving Average (EMA)

**Purpose**: More responsive to recent price changes than SMA, using exponential weighting.

**Formula**: 
- EMA = (Close × Multiplier) + (Previous EMA × (1 - Multiplier))
- Multiplier = 2 / (Period + 1)

**Parameters**:
- `prices`: List of decimal prices  
- `period`: Smoothing period (typically 12, 26, 50)

**Example**:
```elixir
prices = [100, 102, 104, 103, 105, 107] |> Enum.map(&Decimal.new/1)
ema_3 = TradingIndicators.Trend.EMA.calculate(prices, 3)
# EMA reacts faster to price changes than SMA
```

**Interpretation**:
- Faster signal generation than SMA
- Less lag, more responsive to recent changes
- Good for trend following strategies

### Weighted Moving Average (WMA)

**Purpose**: Gives more weight to recent prices in a linear fashion.

**Formula**: WMA = (P₁×n + P₂×(n-1) + ... + Pₙ×1) / (n + (n-1) + ... + 1)

**Example**:
```elixir
prices = [100, 101, 102, 103, 104] |> Enum.map(&Decimal.new/1)
wma_3 = TradingIndicators.Trend.WMA.calculate(prices, 3)
# Recent prices have higher impact than older prices
```

### Hull Moving Average (HMA)

**Purpose**: Reduces lag while maintaining smoothness using weighted moving averages.

**Formula**: HMA = WMA(2×WMA(n/2) - WMA(n), √n)

**Example**:
```elixir
prices = [100, 101, 99, 102, 98, 103, 97, 104] |> Enum.map(&Decimal.new/1)
hma_5 = TradingIndicators.Trend.HMA.calculate(prices, 5)
# Faster response with reduced noise
```

### Kaufman's Adaptive Moving Average (KAMA)

**Purpose**: Adapts to market volatility, moving faster in trending markets and slower in choppy markets.

**Parameters**:
- `prices`: Price data
- `period`: Lookback period for efficiency ratio
- `fast_sc`: Fast smoothing constant period
- `slow_sc`: Slow smoothing constant period

**Example**:
```elixir
# Trending market data
trending_prices = 1..30 |> Enum.map(fn i -> Decimal.new(100 + i * 0.5) end)
kama_trend = TradingIndicators.Trend.KAMA.calculate(trending_prices, 10, 2, 30)

# Choppy market data  
choppy_prices = 1..30 |> Enum.map(fn i -> 
  base = 100
  noise = rem(i, 2) * 2 - 1  # Alternating +1/-1
  Decimal.new(base + noise)
end)
kama_choppy = TradingIndicators.Trend.KAMA.calculate(choppy_prices, 10, 2, 30)
```

### MACD (Moving Average Convergence Divergence)

**Purpose**: Shows relationship between two moving averages, revealing momentum changes.

**Components**:
- MACD Line: 12-period EMA - 26-period EMA
- Signal Line: 9-period EMA of MACD Line  
- Histogram: MACD Line - Signal Line

**Example**:
```elixir
prices = 1..100 |> Enum.map(fn i -> 
  Decimal.new(100 + i * 0.1 + :rand.normal() * 2)
end)

macd = TradingIndicators.Trend.MACD.calculate(prices, 12, 26, 9)
%{
  macd: macd_line,
  signal: signal_line, 
  histogram: histogram
} = macd

# Trading signals:
# - MACD crosses above signal: Bullish
# - MACD crosses below signal: Bearish
# - Histogram divergence: Momentum change
```

## Momentum Indicators

Momentum indicators measure the rate of price change and help identify overbought/oversold conditions.

### Relative Strength Index (RSI)

**Purpose**: Measures momentum, oscillates between 0-100 to identify overbought/oversold conditions.

**Formula**:
- RSI = 100 - (100 / (1 + RS))
- RS = Average Gain / Average Loss

**Parameters**:
- `prices`: Price data
- `period`: Calculation period (typically 14)

**Example**:
```elixir
# Generate trending price data
prices = 1..50 |> Enum.map(fn i -> 
  Decimal.new(100 + i * 0.5 + :rand.normal())
end)

rsi = TradingIndicators.Momentum.RSI.calculate(prices, 14)

# Interpretation:
# RSI > 70: Potentially overbought
# RSI < 30: Potentially oversold  
# RSI around 50: Neutral momentum
```

### Stochastic Oscillator

**Purpose**: Compares closing price to high-low range over a period.

**Components**:
- %K = ((Close - LowestLow) / (HighestHigh - LowestLow)) × 100
- %D = SMA of %K

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(50)

stochastic = TradingIndicators.Momentum.Stochastic.calculate(ohlcv_data, 14, 3)
%{k: k_values, d: d_values} = stochastic

# Signals:
# %K > 80: Overbought
# %K < 20: Oversold
# %K crosses above %D: Bullish signal
# %K crosses below %D: Bearish signal
```

### Commodity Channel Index (CCI)

**Purpose**: Identifies cyclical turns in commodities and other markets.

**Formula**: CCI = (Typical Price - SMA) / (0.015 × Mean Deviation)

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(30)
cci = TradingIndicators.Momentum.CCI.calculate(ohlcv_data, 20)

# Interpretation:
# CCI > +100: Strong uptrend
# CCI < -100: Strong downtrend  
# CCI between -100 and +100: Weak trend
```

### Rate of Change (ROC)

**Purpose**: Measures percentage change in price over a specified period.

**Formula**: ROC = ((Current Price - Price n periods ago) / Price n periods ago) × 100

**Example**:
```elixir
prices = [100, 102, 104, 106, 108, 110] |> Enum.map(&Decimal.new/1)
roc_3 = TradingIndicators.Momentum.ROC.calculate(prices, 3)

# Positive ROC: Price increasing
# Negative ROC: Price decreasing
# Zero ROC: No change
```

### Williams %R

**Purpose**: Momentum oscillator measuring overbought/oversold levels.

**Formula**: %R = ((Highest High - Close) / (Highest High - Lowest Low)) × -100

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(25)
williams_r = TradingIndicators.Momentum.WilliamsR.calculate(ohlcv_data, 14)

# Values range from -100 to 0:
# %R > -20: Overbought
# %R < -80: Oversold
```

## Volatility Indicators

Volatility indicators measure market volatility and help identify potential breakouts or periods of consolidation.

### Average True Range (ATR)

**Purpose**: Measures market volatility by calculating average of true ranges.

**True Range**: Maximum of:
- High - Low
- |High - Previous Close|
- |Low - Previous Close|

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(30)
atr = TradingIndicators.Volatility.ATR.calculate(ohlcv_data, 14)

# Higher ATR: More volatile market
# Lower ATR: Less volatile market
# Use for position sizing and stop losses
```

### Bollinger Bands

**Purpose**: Shows relative high and low prices using standard deviation bands.

**Components**:
- Upper Band: SMA + (Standard Deviation × Multiplier)
- Middle Band: SMA
- Lower Band: SMA - (Standard Deviation × Multiplier)

**Example**:
```elixir
prices = 1..50 |> Enum.map(fn i -> 
  Decimal.new(100 + :rand.normal() * 5)
end)

bands = TradingIndicators.Volatility.BollingerBands.calculate(prices, 20, Decimal.new("2.0"))
%{upper: upper, middle: middle, lower: lower} = bands

# Trading signals:
# Price touching upper band: Potentially overbought
# Price touching lower band: Potentially oversold
# Band width indicates volatility
```

### Standard Deviation

**Purpose**: Measures price variability around the mean.

**Example**:
```elixir
prices = [95, 98, 102, 99, 101, 97, 103] |> Enum.map(&Decimal.new/1)
std_dev = TradingIndicators.Volatility.StandardDeviation.calculate(prices, 5)

# Higher values: More volatile
# Lower values: More stable
```

### Volatility Index

**Purpose**: Normalized measure of price volatility.

**Example**:
```elixir
prices = TradingIndicators.TestSupport.DataGenerator.sample_prices(50)
vol_index = TradingIndicators.Volatility.VolatilityIndex.calculate(prices, 20)

# Values typically range 0-100
# Higher values indicate higher volatility
```

## Volume Indicators

Volume indicators analyze trading volume to confirm price movements and identify potential reversals.

### On-Balance Volume (OBV)

**Purpose**: Accumulates volume based on price direction.

**Logic**:
- If Close > Previous Close: Add volume
- If Close < Previous Close: Subtract volume  
- If Close = Previous Close: No change

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(30)
obv = TradingIndicators.Volume.OBV.calculate(ohlcv_data)

# Rising OBV with rising prices: Confirms uptrend
# Falling OBV with falling prices: Confirms downtrend
# OBV divergence: Potential reversal signal
```

### Volume Weighted Average Price (VWAP)

**Purpose**: Average price weighted by volume, showing true average price.

**Formula**: VWAP = Σ(Price × Volume) / Σ(Volume)

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(25)
vwap = TradingIndicators.Volume.VWAP.calculate(ohlcv_data)

# Price above VWAP: Bullish bias
# Price below VWAP: Bearish bias
# VWAP acts as dynamic support/resistance
```

### Accumulation/Distribution Line (A/D)

**Purpose**: Measures money flow to determine if accumulation or distribution is occurring.

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(40)
ad_line = TradingIndicators.Volume.AccumulationDistribution.calculate(ohlcv_data)

# Rising A/D: Accumulation (buying pressure)
# Falling A/D: Distribution (selling pressure)
```

### Chaikin Money Flow (CMF)

**Purpose**: Measures money flow over a specific period.

**Example**:
```elixir
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(30)
cmf = TradingIndicators.Volume.ChaikinMoneyFlow.calculate(ohlcv_data, 20)

# CMF > 0: Buying pressure
# CMF < 0: Selling pressure
# Values range approximately -1.0 to +1.0
```

## Practical Trading Examples

### Multi-Indicator Analysis

```elixir
defmodule TradingAnalysis do
  def comprehensive_analysis(ohlcv_data) do
    prices = Enum.map(ohlcv_data, & &1.close)
    
    %{
      # Trend Analysis
      sma_20: TradingIndicators.Trend.SMA.calculate(prices, 20),
      ema_12: TradingIndicators.Trend.EMA.calculate(prices, 12),
      macd: TradingIndicators.Trend.MACD.calculate(prices, 12, 26, 9),
      
      # Momentum Analysis  
      rsi: TradingIndicators.Momentum.RSI.calculate(prices, 14),
      stochastic: TradingIndicators.Momentum.Stochastic.calculate(ohlcv_data, 14, 3),
      
      # Volatility Analysis
      atr: TradingIndicators.Volatility.ATR.calculate(ohlcv_data, 14),
      bollinger: TradingIndicators.Volatility.BollingerBands.calculate(prices, 20, Decimal.new("2.0")),
      
      # Volume Analysis
      obv: TradingIndicators.Volume.OBV.calculate(ohlcv_data),
      vwap: TradingIndicators.Volume.VWAP.calculate(ohlcv_data)
    }
  end
  
  def generate_signals(analysis) do
    current_price = List.last(analysis.prices)
    current_rsi = List.last(analysis.rsi)
    current_macd = List.last(analysis.macd.histogram)
    
    signals = []
    
    # RSI signals
    signals = if Decimal.gt?(current_rsi, Decimal.new("70")) do
      [:overbought | signals]
    else
      signals
    end
    
    signals = if Decimal.lt?(current_rsi, Decimal.new("30")) do
      [:oversold | signals]  
    else
      signals
    end
    
    # MACD signals
    signals = if Decimal.gt?(current_macd, Decimal.new("0")) do
      [:bullish_momentum | signals]
    else
      [:bearish_momentum | signals]
    end
    
    signals
  end
end

# Usage
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(100)
analysis = TradingAnalysis.comprehensive_analysis(ohlcv_data)
signals = TradingAnalysis.generate_signals(analysis)
```

### Custom Indicator Combinations

```elixir
defmodule CustomIndicators do
  def trend_strength_index(prices) do
    short_ma = TradingIndicators.Trend.EMA.calculate(prices, 10)
    long_ma = TradingIndicators.Trend.EMA.calculate(prices, 30)
    
    # Calculate percentage difference
    Enum.zip(short_ma, long_ma)
    |> Enum.map(fn {short, long} ->
      diff = Decimal.sub(short, long)
      pct_diff = Decimal.mult(Decimal.div(diff, long), Decimal.new("100"))
      pct_diff
    end)
  end
  
  def momentum_composite(prices) do
    rsi = TradingIndicators.Momentum.RSI.calculate(prices, 14)
    roc = TradingIndicators.Momentum.ROC.calculate(prices, 10)
    
    # Normalize and combine
    Enum.zip(rsi, roc)
    |> Enum.map(fn {rsi_val, roc_val} ->
      # Simple average (could use weighted average)
      normalized_roc = Decimal.add(Decimal.mult(roc_val, Decimal.new("5")), Decimal.new("50"))
      Decimal.div(Decimal.add(rsi_val, normalized_roc), Decimal.new("2"))
    end)
  end
end
```

## Best Practices

### Parameter Selection
- **SMA/EMA periods**: 10, 20, 50, 200 are common
- **RSI period**: 14 is standard, 7 for short-term, 21 for long-term
- **Bollinger Bands**: 20-period with 2 standard deviations
- **MACD**: 12, 26, 9 are default parameters

### Indicator Combinations
- Use trend + momentum for confirmation
- Combine volume indicators with price indicators  
- Multiple timeframes provide better context
- Avoid over-optimization with too many indicators

### Risk Management
- Use ATR for position sizing
- Bollinger Bands for volatility-adjusted stops
- Multiple indicator confirmation reduces false signals
- Backtest strategies before live trading

### Performance Considerations
- Cache frequently calculated indicators
- Use streaming for real-time applications
- Consider computational complexity for large datasets
- Monitor memory usage with large historical data

This guide covers the mathematical foundations and practical applications of all indicators in the TradingIndicators library. Each indicator has been implemented with proper error handling, comprehensive testing, and optimized performance for professional trading applications.