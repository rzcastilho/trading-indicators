# Getting Started with TradingIndicators

Welcome to TradingIndicators, a comprehensive Elixir library for technical analysis of financial markets. This guide will help you get started with basic usage and concepts.

## Installation

Add TradingIndicators to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:trading_indicators, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Basic Concepts

### Data Format

TradingIndicators works with two main data formats:

1. **Price Series** - Simple list of decimal prices:
   ```elixir
   prices = [
     Decimal.new("100.50"),
     Decimal.new("101.25"),
     Decimal.new("102.10")
   ]
   ```

2. **OHLCV Data** - Complete market data with Open, High, Low, Close, Volume:
   ```elixir
   ohlcv_data = [
     %{
       open: Decimal.new("100.00"),
       high: Decimal.new("102.50"),
       low: Decimal.new("99.75"),
       close: Decimal.new("101.25"),
       volume: 150000,
       timestamp: ~U[2024-01-01 09:30:00Z]
     }
   ]
   ```

### Decimal Precision

All calculations use the `Decimal` library for precise financial calculations, avoiding floating-point precision issues common in financial computations.

## Quick Start Examples

### Simple Moving Average (SMA)

```elixir
# Calculate 20-period SMA
prices = [100.0, 101.0, 102.0, 103.0, 104.0] 
|> Enum.map(&Decimal.new/1)

sma_result = TradingIndicators.Trend.SMA.calculate(prices, 3)
# Result: [Decimal.new("101.0"), Decimal.new("102.0"), Decimal.new("103.0")]
```

### Relative Strength Index (RSI)

```elixir
# Generate sample data
prices = 1..50
|> Enum.map(fn i -> 100 + :rand.normal() * 5 end)
|> Enum.map(&Decimal.from_float/1)

# Calculate 14-period RSI
rsi_values = TradingIndicators.Momentum.RSI.calculate(prices, 14)

# RSI values will be between 0 and 100
IO.inspect(List.last(rsi_values)) # Current RSI value
```

### Bollinger Bands

```elixir
prices = [95.0, 96.5, 98.0, 99.5, 101.0, 102.5, 104.0, 103.5, 102.0, 100.5]
|> Enum.map(&Decimal.new/1)

# Calculate Bollinger Bands (20-period, 2 standard deviations)
bands = TradingIndicators.Volatility.BollingerBands.calculate(prices, 5, Decimal.new("2.0"))

%{
  upper: upper_band,
  middle: middle_band,  # This is the SMA
  lower: lower_band
} = bands

IO.puts("Upper: #{List.last(upper_band)}")
IO.puts("Middle: #{List.last(middle_band)}")  
IO.puts("Lower: #{List.last(lower_band)}")
```

### OHLCV Indicators

For indicators requiring OHLCV data:

```elixir
# Generate sample OHLCV data
ohlcv_data = TradingIndicators.TestSupport.DataGenerator.sample_ohlcv_data(50)

# Calculate Average True Range (ATR)
atr_values = TradingIndicators.Volatility.ATR.calculate(ohlcv_data, 14)

# Calculate Stochastic Oscillator
stochastic = TradingIndicators.Momentum.Stochastic.calculate(ohlcv_data, 14, 3)
%{k: k_values, d: d_values} = stochastic
```

## Working with Pipelines

For complex analysis involving multiple indicators:

```elixir
# Create a pipeline
pipeline = TradingIndicators.Pipeline.new()
|> TradingIndicators.Pipeline.add_indicator(:sma_20, {TradingIndicators.Trend.SMA, :calculate, [20]})
|> TradingIndicators.Pipeline.add_indicator(:rsi, {TradingIndicators.Momentum.RSI, :calculate, [14]})
|> TradingIndicators.Pipeline.add_indicator(:bb, {TradingIndicators.Volatility.BollingerBands, :calculate, [20, Decimal.new("2.0")]})

# Run pipeline on your data
results = TradingIndicators.Pipeline.run(pipeline, prices)

# Access results
sma_values = results.sma_20
rsi_values = results.rsi
bollinger_bands = results.bb
```

## Streaming Data

For real-time applications:

```elixir
# Initialize streaming context
{:ok, context} = TradingIndicators.Streaming.initialize(
  TradingIndicators.Trend.SMA, 
  :calculate, 
  [10]
)

# Update with new data points
{context, result1} = TradingIndicators.Streaming.update(context, Decimal.new("100.0"))
{context, result2} = TradingIndicators.Streaming.update(context, Decimal.new("101.0"))
# ... continue updating with new prices
```

## Error Handling

The library provides comprehensive error handling:

```elixir
try do
  # This will raise an error - period too large for data
  TradingIndicators.Trend.SMA.calculate([Decimal.new("100")], 5)
rescue
  TradingIndicators.Errors.InsufficientDataError ->
    IO.puts("Not enough data for calculation")
end
```

## Data Quality Validation

Validate your data before processing:

```elixir
case TradingIndicators.DataQuality.validate_ohlcv_data(ohlcv_data) do
  :ok -> 
    # Data is valid, proceed with calculations
    atr = TradingIndicators.Volatility.ATR.calculate(ohlcv_data, 14)
    
  {:error, reason} ->
    IO.puts("Data validation failed: #{reason}")
end
```

## Next Steps

- Read the [Indicators Guide](indicators-guide.md) for detailed information about each indicator
- Check the [Performance Guide](performance-guide.md) for optimization tips
- Explore the [Architecture Guide](architecture.md) to understand the library design
- Run the comprehensive test suite: `mix test --include property --include integration`
- Generate benchmarks: `mix run benchmarks/indicator_benchmarks.exs`

## Common Patterns

### Indicator Composition

```elixir
# Combine multiple timeframes
short_sma = TradingIndicators.Trend.SMA.calculate(prices, 10)
long_sma = TradingIndicators.Trend.SMA.calculate(prices, 20)

# Create signals
signals = Enum.zip(short_sma, long_sma)
|> Enum.map(fn {short, long} ->
  cond do
    Decimal.gt?(short, long) -> :bullish
    Decimal.lt?(short, long) -> :bearish  
    true -> :neutral
  end
end)
```

### Custom Analysis Functions

```elixir
defmodule MyAnalysis do
  def trend_strength(prices) do
    sma_10 = TradingIndicators.Trend.SMA.calculate(prices, 10)
    sma_20 = TradingIndicators.Trend.SMA.calculate(prices, 20) 
    rsi = TradingIndicators.Momentum.RSI.calculate(prices, 14)
    
    # Combine indicators for trend strength analysis
    %{
      moving_average_trend: analyze_ma_trend(sma_10, sma_20),
      momentum: List.last(rsi),
      strength: calculate_strength(sma_10, sma_20, rsi)
    }
  end
  
  defp analyze_ma_trend(short_ma, long_ma) do
    # Implementation details...
  end
  
  defp calculate_strength(short_ma, long_ma, rsi) do
    # Implementation details...
  end
end
```

## Support and Documentation

- Full API documentation: `mix docs`
- Run tests: `mix test`
- Code quality checks: `mix check`
- Performance analysis: `mix run benchmarks/indicator_benchmarks.exs`

Happy trading! 📈