defmodule TradingIndicators do
  @moduledoc """
  A comprehensive Elixir library for trading indicators with consistent APIs, proper error handling, and extensible architecture.

  TradingIndicators provides a wide range of technical analysis indicators commonly used in
  financial markets, including trend, momentum, volatility, and volume indicators.

  ## Features

  - **Comprehensive Indicator Set**: Support for major trading indicators including SMA, EMA, RSI, MACD, Bollinger Bands, and more
  - **Consistent API**: All indicators follow the same behavior pattern for predictable usage
  - **Streaming Support**: Real-time indicator calculations with state management
  - **Type Safety**: Comprehensive type specifications and data validation
  - **Error Handling**: Detailed error messages with actionable information
  - **Performance**: Optimized for both batch processing and real-time streaming
  - **Extensible**: Easy to add custom indicators following the established patterns

  ## Quick Start

      # For batch processing
      data = [
        %{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{open: Decimal.new("103.0"), high: Decimal.new("107.0"), low: Decimal.new("102.0"), close: Decimal.new("106.0"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]},
        # ... more data
      ]

      # Calculate Simple Moving Average
      {:ok, results} = TradingIndicators.Trend.SMA.calculate(data, period: 14)

      # Calculate RSI
      {:ok, rsi_values} = TradingIndicators.Momentum.RSI.calculate(data, period: 14)

  ## Architecture

  The library is organized into several categories:

  - `TradingIndicators.Trend` - Trend-following indicators (SMA, EMA, MACD, etc.)
  - `TradingIndicators.Momentum` - Momentum oscillators (RSI, Stochastic, Williams %R, etc.)
  - `TradingIndicators.Volatility` - Volatility indicators (Bollinger Bands, ATR, etc.)
  - `TradingIndicators.Volume` - Volume-based indicators (OBV, VWAP, etc.)

  ## Core Concepts

  ### Data Types

  All indicators work with standardized OHLCV data structures:

      %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

  ### Indicator Behavior

  All indicators implement the `TradingIndicators.Behaviour` which defines:

  - `calculate/2` - Batch processing of historical data
  - `validate_params/1` - Parameter validation
  - `required_periods/0` - Minimum data requirements
  - `init_state/1` and `update_state/2` - (Optional) Streaming support

  ### Error Handling

  The library uses specific exception types for clear error reporting:

  - `TradingIndicators.Errors.InsufficientData` - Not enough data for calculation
  - `TradingIndicators.Errors.InvalidParams` - Invalid parameters
  - `TradingIndicators.Errors.InvalidDataFormat` - Malformed input data
  - `TradingIndicators.Errors.CalculationError` - Mathematical calculation errors

  ## Performance Considerations

  - Use streaming mode for real-time applications to avoid recalculating entire datasets
  - Batch mode is optimized for historical data analysis
  - Consider using `TradingIndicators.Pipeline` for complex multi-indicator calculations
  - Large datasets benefit from parallel processing capabilities

  ## Contributing

  The library follows strict coding standards:

  - All public functions must have type specifications
  - Comprehensive test coverage (>95%)
  - Documentation with examples for all public APIs
  - Follow the established indicator behavior pattern
  """

  alias TradingIndicators.Types
  alias TradingIndicators.Utils

  @doc """
  Returns the version of the TradingIndicators library.

  ## Examples

      iex> TradingIndicators.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:trading_indicators, :vsn) |> to_string()
  end

  @doc """
  Lists all available indicator categories.

  ## Returns

  List of modules representing indicator categories.

  ## Examples

      iex> TradingIndicators.categories()
      []
  """
  @spec categories() :: [module()]
  def categories do
    [
      # Will be implemented in subsequent phases
      # TradingIndicators.Trend,
      # TradingIndicators.Momentum,
      # TradingIndicators.Volatility,
      # TradingIndicators.Volume
    ]
  end

  @doc """
  Validates OHLCV data series for indicator calculations.

  ## Parameters

  - `data` - List of OHLCV data points to validate

  ## Returns

  - `:ok` - Data is valid
  - `{:error, reason}` - Data validation failed with reason

  ## Examples

      iex> data = [%{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]
      iex> TradingIndicators.validate_data(data)
      :ok

      iex> {:error, error} = TradingIndicators.validate_data([])
      iex> error.message
      "Data series cannot be empty"
  """
  @spec validate_data(Types.data_series()) :: :ok | {:error, Exception.t()}
  def validate_data([]) do
    {:error,
     %TradingIndicators.Errors.InsufficientData{
       message: "Data series cannot be empty",
       required: 1,
       provided: 0
     }}
  end

  def validate_data(data) when is_list(data) do
    case validate_ohlcv_series(data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_data(_data) do
    {:error,
     %TradingIndicators.Errors.InvalidDataFormat{
       message: "Data must be a list of OHLCV maps",
       expected: "list of OHLCV maps",
       received: "invalid format"
     }}
  end

  # Private helper to validate OHLCV series
  defp validate_ohlcv_series(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {data_point, index}, _acc ->
      if Types.valid_ohlcv?(data_point) do
        {:cont, :ok}
      else
        error = %TradingIndicators.Errors.InvalidDataFormat{
          message: "Invalid OHLCV data at index #{index}",
          expected: "OHLCV map with keys: [:open, :high, :low, :close, :volume, :timestamp]",
          received: "invalid or incomplete OHLCV data",
          index: index
        }

        {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  Extracts price series from OHLCV data by specified source.

  ## Parameters

  - `data` - List of OHLCV data points
  - `source` - Price source (`:open`, `:high`, `:low`, `:close`)

  ## Returns

  - List of price values

  ## Examples

      iex> data = [%{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]
      iex> TradingIndicators.extract_price_series(data, :close)
      [Decimal.new("103.0")]

      iex> sample_data = [%{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]
      iex> TradingIndicators.extract_price_series(sample_data, :high)
      [Decimal.new("105.0")]
  """
  @spec extract_price_series(Types.data_series(), :open | :high | :low | :close) :: [Decimal.t()]
  def extract_price_series(data, :open), do: Utils.extract_opens(data)
  def extract_price_series(data, :high), do: Utils.extract_highs(data)
  def extract_price_series(data, :low), do: Utils.extract_lows(data)
  def extract_price_series(data, :close), do: Utils.extract_closes(data)

  @doc """
  Creates a standardized indicator result.

  ## Parameters

  - `value` - The calculated indicator value
  - `timestamp` - The timestamp for this calculation
  - `metadata` - Optional metadata about the calculation

  ## Returns

  - Standardized indicator result map

  ## Examples

      iex> TradingIndicators.create_result(Decimal.new("14.5"), ~U[2024-01-01 09:30:00Z], %{period: 14})
      %{value: Decimal.new("14.5"), timestamp: ~U[2024-01-01 09:30:00Z], metadata: %{period: 14}}
  """
  @spec create_result(term(), DateTime.t(), map()) :: Types.indicator_result()
  def create_result(value, timestamp, metadata \\ %{}) do
    %{
      value: value,
      timestamp: timestamp,
      metadata: metadata
    }
  end
end
