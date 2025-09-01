# TradingIndicators

[![Hex.pm](https://img.shields.io/hexpm/v/trading_indicators.svg)](https://hex.pm/packages/trading_indicators)
[![Documentation](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/trading_indicators/)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/rzcastilho/trading_indicators/blob/main/LICENSE)

A comprehensive Elixir library for technical analysis with **22 trading indicators** across 4 categories. Built with precision using the Decimal library for financial accuracy, featuring consistent APIs, robust error handling, and real-time streaming support.

## ✨ Features

- **📊 22 Trading Indicators** across 4 categories (Trend, Momentum, Volatility, Volume)
- **🎯 Decimal Precision** - Uses Decimal library to eliminate floating-point errors
- **⚡ Real-time Streaming** - All indicators support streaming/incremental updates
- **🛡️ Robust Error Handling** - Comprehensive validation with meaningful error messages
- **🧪 Extensively Tested** - 709 tests with 92 doctests, 100% success rate
- **📚 Complete Documentation** - Detailed docs with examples and mathematical formulas
- **🏗️ Consistent API** - Uniform interface across all indicators
- **⚙️ Highly Configurable** - Customizable periods, sources, and parameters

## 🚀 Quick Start

Add `trading_indicators` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trading_indicators, "~> 0.1.0"}
  ]
end
```

### Basic Usage

```elixir
# Sample OHLCV data
data = [
  %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("95"), 
    close: Decimal.new("102"), volume: Decimal.new("1000"), timestamp: ~U[2024-01-01 09:30:00Z]},
  %{open: Decimal.new("102"), high: Decimal.new("107"), low: Decimal.new("97"), 
    close: Decimal.new("104"), volume: Decimal.new("1200"), timestamp: ~U[2024-01-01 09:31:00Z]},
  # ... more data points
]

# Calculate indicators
alias TradingIndicators.{Trend, Momentum, Volatility, Volume}

# Trend indicators
{:ok, sma_results} = Trend.sma(data, period: 20)
{:ok, ema_results} = Trend.ema(data, period: 12) 
{:ok, macd_results} = Trend.macd(data, fast_period: 12, slow_period: 26, signal_period: 9)

# Momentum indicators  
{:ok, rsi_results} = Momentum.rsi(data, period: 14)
{:ok, stoch_results} = Momentum.stochastic(data, k_period: 14, d_period: 3)

# Volatility indicators
{:ok, bb_results} = Volatility.bollinger_bands(data, period: 20, multiplier: Decimal.new("2.0"))
{:ok, atr_results} = Volatility.atr(data, period: 14)

# Volume indicators (require volume data)
{:ok, obv_results} = Volume.obv(data)
{:ok, vwap_results} = Volume.vwap(data, variant: :typical)
```

### Real-time Streaming

```elixir
# Initialize streaming state
alias TradingIndicators.{Trend, Momentum}

sma_state = Trend.init_stream(Trend.SMA, period: 20)
rsi_state = Momentum.init_stream(Momentum.RSI, period: 14)

# Process data points as they arrive
new_data_point = %{close: Decimal.new("105"), timestamp: DateTime.utc_now()}

{:ok, new_sma_state, sma_result} = Trend.update_stream(sma_state, new_data_point)
{:ok, new_rsi_state, rsi_result} = Momentum.update_stream(rsi_state, new_data_point)

# Results are nil until sufficient data is available
if sma_result do
  IO.puts("SMA: #{sma_result.value}")
end
```

## 📊 Available Indicators

### 📈 Trend Indicators (6)
- **SMA** - Simple Moving Average
- **EMA** - Exponential Moving Average  
- **WMA** - Weighted Moving Average
- **HMA** - Hull Moving Average
- **KAMA** - Kaufman's Adaptive Moving Average
- **MACD** - Moving Average Convergence Divergence

### ⚡ Momentum Indicators (6)
- **RSI** - Relative Strength Index
- **Stochastic** - Stochastic Oscillator (%K, %D)
- **Williams %R** - Williams Percent Range
- **CCI** - Commodity Channel Index
- **ROC** - Rate of Change
- **Momentum** - Price Momentum

### 🌊 Volatility Indicators (4)
- **Bollinger Bands** - Price channels with standard deviation bands
- **ATR** - Average True Range
- **Standard Deviation** - Price dispersion measurement
- **Volatility Index** - Historical volatility calculation

### 📊 Volume Indicators (4)
- **OBV** - On-Balance Volume
- **VWAP** - Volume Weighted Average Price
- **A/D Line** - Accumulation/Distribution Line
- **CMF** - Chaikin Money Flow

### 🎯 Advanced Features

## 💾 Data Formats

The library accepts OHLCV data in map format with Decimal values:

```elixir
# Full OHLCV format (recommended)
%{
  open: Decimal.new("100.50"),
  high: Decimal.new("102.75"), 
  low: Decimal.new("99.25"),
  close: Decimal.new("101.00"),
  volume: Decimal.new("150000"),  # Required for volume indicators
  timestamp: ~U[2024-01-01 09:30:00Z]
}

# Price series format (for price-only indicators)
[Decimal.new("100"), Decimal.new("101"), Decimal.new("102")]
```

## 🔧 Configuration Options

### Common Parameters
- `:period` - Lookback period (default varies by indicator)
- `:source` - Price source (`:open`, `:high`, `:low`, `:close`)
- `:smoothing` - Additional smoothing periods where applicable

### Indicator-Specific Options

```elixir
# Bollinger Bands
Volatility.bollinger_bands(data, 
  period: 20, 
  multiplier: Decimal.new("2.0"),
  source: :close
)

# MACD
Trend.macd(data,
  fast_period: 12,
  slow_period: 26, 
  signal_period: 9,
  source: :close
)

# RSI  
Momentum.rsi(data,
  period: 14,
  overbought: Decimal.new("70"),
  oversold: Decimal.new("30")
)

# VWAP with session reset
Volume.vwap(data,
  variant: :typical,        # :close, :typical, :weighted
  session_reset: :daily     # :none, :daily, :weekly, :monthly  
)
```

## 📊 Result Format

All indicators return results in a consistent format:

```elixir
%{
  value: Decimal.t(),           # The calculated indicator value
  timestamp: DateTime.t(),      # When this value applies  
  metadata: %{                  # Indicator-specific metadata
    indicator: "SMA",
    period: 20,
    source: :close,
    signal: :neutral            # :bullish, :bearish, :neutral
    # ... additional metadata varies by indicator
  }
}
```

## 🔄 Streaming API

All indicators support real-time streaming for incremental data processing:

### Initialize Stream
```elixir
# Category module convenience
state = Trend.init_stream(Trend.SMA, period: 20)
state = Momentum.init_stream(Momentum.RSI, period: 14)

# Direct indicator initialization  
state = TradingIndicators.Trend.SMA.init_state(period: 20)
```

### Update Stream
```elixir
# Process new data points
{:ok, new_state, result} = Trend.update_stream(state, data_point)

# Result is nil until sufficient data available
case result do
  nil -> :insufficient_data
  %{value: value} -> process_indicator_value(value)
end
```

### Stream State Management
```elixir
# Check if stream has sufficient data
sufficient? = Trend.has_sufficient_data?(state)

# Reset stream state
fresh_state = Trend.reset_stream(state)
```

## 🧮 Mathematical Precision

The library uses the [Decimal](https://hex.pm/packages/decimal) library for all calculations to ensure financial precision:

```elixir
# Automatic conversion from strings/integers
data = [%{close: Decimal.new("100.123456"), timestamp: DateTime.utc_now()}]

# Maintains precision throughout calculations
{:ok, [result]} = Trend.sma(data, period: 1)
result.value  # #Decimal<100.123456>

# Convert to float only when needed for display
Decimal.to_float(result.value)  # 100.123456
```

## 🛡️ Error Handling

Comprehensive error handling with specific error types:

```elixir
# Insufficient data
{:error, %TradingIndicators.Errors.InsufficientData{
  message: "Insufficient data: required 20, got 10",
  required: 20,
  provided: 10
}}

# Invalid parameters
{:error, %TradingIndicators.Errors.InvalidParams{
  message: "period must be a positive integer, got -5",
  param: :period,
  value: -5,
  expected: "positive integer"  
}}

# Invalid data format
{:error, %TradingIndicators.Errors.InvalidDataFormat{
  message: "Expected OHLCV map, got integer",
  expected: "map with :close key",
  received: "integer"
}}
```

## 🧪 Testing & Quality

- **709 tests** (92 doctests + 617 unit tests)
- **100% success rate** - All tests passing
- **Comprehensive coverage** - Edge cases, mathematical accuracy, streaming scenarios
- **Property-based testing** - Using StreamData for robust validation
- **Zero compilation warnings** - Clean, professional code

Run tests:
```bash
mix test
mix test --cover  # With coverage report
```

## 📚 Documentation

Generate documentation:
```bash
mix docs
open doc/index.html
```

Each indicator includes:
- Mathematical formulas and explanations
- Usage examples with sample data
- Parameter descriptions and defaults  
- Trading interpretation guidelines
- Streaming usage patterns

## 🏗️ Architecture

The library follows a consistent architecture pattern:

### Behavior Contract
All indicators implement `TradingIndicators.Behaviour`:
```elixir
@callback calculate(data :: list(), opts :: keyword()) :: 
  {:ok, list()} | {:error, term()}
@callback validate_params(opts :: keyword()) :: 
  :ok | {:error, Exception.t()}
@callback required_periods() :: pos_integer()

# Optional streaming callbacks
@callback init_state(opts :: keyword()) :: map()  
@callback update_state(state :: map(), data_point :: term()) ::
  {:ok, map(), result() | nil} | {:error, term()}
```

### Category Modules
- `TradingIndicators.Trend` - Trend following indicators
- `TradingIndicators.Momentum` - Momentum oscillators  
- `TradingIndicators.Volatility` - Volatility measures
- `TradingIndicators.Volume` - Volume-based indicators

### Type Safety
Complete type specifications using `@spec` annotations:
```elixir
@spec calculate(Types.data_series(), keyword()) :: 
  {:ok, Types.result_series()} | {:error, term()}
```

## 🔍 Examples

### Portfolio Analysis
```elixir
defmodule PortfolioAnalysis do
  alias TradingIndicators.{Trend, Momentum, Volatility}
  
  def analyze_stock(ohlcv_data) do
    # Trend analysis
    {:ok, sma_20} = Trend.sma(ohlcv_data, period: 20)
    {:ok, sma_50} = Trend.sma(ohlcv_data, period: 50) 
    {:ok, macd} = Trend.macd(ohlcv_data)
    
    # Momentum analysis
    {:ok, rsi} = Momentum.rsi(ohlcv_data, period: 14)
    {:ok, stoch} = Momentum.stochastic(ohlcv_data)
    
    # Volatility analysis
    {:ok, bb} = Volatility.bollinger_bands(ohlcv_data, period: 20)
    {:ok, atr} = Volatility.atr(ohlcv_data, period: 14)
    
    %{
      trend: %{sma_20: sma_20, sma_50: sma_50, macd: macd},
      momentum: %{rsi: rsi, stochastic: stoch},
      volatility: %{bollinger_bands: bb, atr: atr}
    }
  end
end
```

### Real-time Trading Signal
```elixir
defmodule TradingSignals do
  alias TradingIndicators.{Trend, Momentum}
  
  def init_signals do
    %{
      sma_fast: Trend.init_stream(Trend.SMA, period: 10),
      sma_slow: Trend.init_stream(Trend.SMA, period: 20), 
      rsi: Momentum.init_stream(Momentum.RSI, period: 14)
    }
  end
  
  def process_tick(states, tick_data) do
    # Update all indicators
    {:ok, new_sma_fast, sma_fast_result} = 
      Trend.update_stream(states.sma_fast, tick_data)
    {:ok, new_sma_slow, sma_slow_result} = 
      Trend.update_stream(states.sma_slow, tick_data)  
    {:ok, new_rsi, rsi_result} = 
      Momentum.update_stream(states.rsi, tick_data)
      
    # Generate signals
    signal = generate_signal(sma_fast_result, sma_slow_result, rsi_result)
    
    new_states = %{
      sma_fast: new_sma_fast,
      sma_slow: new_sma_slow,
      rsi: new_rsi
    }
    
    {new_states, signal}
  end
  
  defp generate_signal(sma_fast, sma_slow, rsi) do
    cond do
      sma_fast && sma_slow && rsi &&
      Decimal.gt?(sma_fast.value, sma_slow.value) && 
      Decimal.lt?(rsi.value, Decimal.new("30")) ->
        :buy_signal
        
      sma_fast && sma_slow && rsi &&
      Decimal.lt?(sma_fast.value, sma_slow.value) &&
      Decimal.gt?(rsi.value, Decimal.new("70")) ->
        :sell_signal
        
      true ->
        :no_signal
    end
  end
end
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-indicator`)
3. Run tests (`mix test`) 
4. Add tests for new indicators
5. Ensure code coverage remains high
6. Update documentation
7. Commit your changes (`git commit -am 'Add amazing indicator'`)
8. Push to the branch (`git push origin feature/amazing-indicator`)
9. Create a Pull Request

## 📋 Roadmap

- [ ] **Phase 6**: Advanced Features & Optimization
- [ ] **Phase 7**: Testing, Documentation & Quality  
- [ ] **Phase 8**: Release Preparation & Hex Publishing
- [ ] Additional indicators (Ichimoku, Fibonacci, etc.)
- [ ] Performance benchmarking suite
- [ ] WebSocket streaming adapters
- [ ] Chart visualization helpers

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) for robust concurrent processing
- Uses [Decimal](https://hex.pm/packages/decimal) for financial precision  
- Inspired by industry-standard technical analysis formulas
- Tested with [ExUnit](https://hexdocs.pm/ex_unit/) and [StreamData](https://hex.pm/packages/stream_data)

---

**TradingIndicators** - Professional-grade technical analysis for Elixir applications