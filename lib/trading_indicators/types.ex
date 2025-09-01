defmodule TradingIndicators.Types do
  require Decimal
  
  @moduledoc """
  Common data structures and type definitions for the TradingIndicators library.

  This module defines all the shared types used throughout the library,
  ensuring consistency in data handling and API design.

  ## Core Data Types

  - `ohlcv/0` - Open, High, Low, Close, Volume data point
  - `indicator_result/0` - Standardized indicator calculation result
  - `data_series/0` - Series of OHLCV data points
  - `result_series/0` - Series of indicator results

  ## Price Series Types

  - `price_series/0` - Generic price data series
  - `close_series/0` - Series of closing prices
  - `high_series/0` - Series of high prices
  - `low_series/0` - Series of low prices
  - `volume_series/0` - Series of volume data
  """

  @typedoc """
  OHLCV (Open, High, Low, Close, Volume) data point.

  Represents a single period of market data with all essential price and volume information.
  The timestamp field allows for proper time series ordering and validation.

  ## Fields

  - `:open` - Opening price for the period
  - `:high` - Highest price during the period
  - `:low` - Lowest price during the period
  - `:close` - Closing price for the period
  - `:volume` - Trading volume during the period
  - `:timestamp` - Time when this data point occurred

  ## Example

      %{
        open: Decimal.new("100.00"),
        high: Decimal.new("105.00"),
        low: Decimal.new("99.00"),
        close: Decimal.new("103.00"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }
  """
  @type ohlcv :: %{
          open: Decimal.t(),
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          volume: non_neg_integer(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Standardized result structure for indicator calculations.

  Provides a consistent format for all indicator results, including the calculated
  value, timestamp, and optional metadata for additional information.

  ## Fields

  - `:value` - The calculated indicator value (can be number or complex structure)
  - `:timestamp` - Timestamp associated with this calculation
  - `:metadata` - Additional information about the calculation (optional)

  ## Example

      %{
        value: Decimal.new("14.5"),
        timestamp: ~U[2024-01-01 09:30:00Z],
        metadata: %{period: 14, source: :close}
      }
  """
  @type indicator_result :: %{
          value: Decimal.t() | integer() | map(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @typedoc """
  Series of OHLCV data points.

  Represents a time-ordered sequence of market data, typically used as input
  for indicator calculations.
  """
  @type data_series :: [ohlcv()]

  @typedoc """
  Series of indicator calculation results.

  Represents the output of indicator calculations, maintaining time ordering
  and providing standardized result format.
  """
  @type result_series :: [indicator_result()]

  @typedoc """
  Generic price series - list of numerical price values.

  Used for simplified calculations that only require a single price series
  (e.g., closing prices, high prices, etc.).
  """
  @type price_series :: [Decimal.t()]

  @typedoc """
  Series of closing prices extracted from OHLCV data.
  """
  @type close_series :: [Decimal.t()]

  @typedoc """
  Series of high prices extracted from OHLCV data.
  """
  @type high_series :: [Decimal.t()]

  @typedoc """
  Series of low prices extracted from OHLCV data.
  """
  @type low_series :: [Decimal.t()]

  @typedoc """
  Series of opening prices extracted from OHLCV data.
  """
  @type open_series :: [Decimal.t()]

  @typedoc """
  Series of volume data extracted from OHLCV data.
  """
  @type volume_series :: [non_neg_integer()]

  @typedoc """
  Combined high-low-close data used by some indicators.

  Some indicators require multiple price points from each period.
  This type represents the common HLC combination.
  """
  @type hlc_data :: %{
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of HLC data points.
  """
  @type hlc_series :: [hlc_data()]

  @typedoc """
  Typical Price calculation result.

  The typical price is calculated as (high + low + close) / 3
  and is used by various indicators like CCI.
  """
  @type typical_price :: %{
          value: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of typical price calculations.
  """
  @type typical_price_series :: [typical_price()]

  @typedoc """
  True Range calculation result.

  True Range is the maximum of:
  - Current High - Current Low
  - Current High - Previous Close (absolute value)
  - Current Low - Previous Close (absolute value)
  """
  @type true_range :: %{
          value: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of True Range calculations.
  """
  @type true_range_series :: [true_range()]

  @typedoc """
  Bollinger Bands calculation result.

  Contains all three bands plus additional calculations:
  - Upper Band: SMA + (multiplier × standard deviation)
  - Middle Band: Simple Moving Average
  - Lower Band: SMA - (multiplier × standard deviation)  
  - %B: Position of price relative to bands ((Price - Lower) / (Upper - Lower) × 100)
  - Bandwidth: Distance between bands ((Upper - Lower) / Middle × 100)
  """
  @type bollinger_result :: %{
          upper_band: Decimal.t(),
          middle_band: Decimal.t(),
          lower_band: Decimal.t(),
          percent_b: Decimal.t(),
          bandwidth: Decimal.t(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @typedoc """
  Options for indicator calculations.

  Common options that can be passed to indicator functions:
  - `:period` - Number of periods to use in calculation
  - `:source` - Source price to use (:open, :high, :low, :close)
  - `:smoothing` - Smoothing factor for EMA-based calculations
  - `:multiplier` - Multiplier for standard deviation bands
  """
  @type indicator_opts :: keyword()

  @typedoc """
  Stream state for real-time indicator calculations.

  Generic type for maintaining state across streaming updates.
  Each indicator implementation defines its own specific state structure.
  """
  @type stream_state :: term()

  @typedoc """
  Validation result for input parameters or data.
  """
  @type validation_result :: :ok | {:error, term()}

  @typedoc """
  Time period specification for indicators.

  Can be specified as:
  - Positive integer (number of periods)
  - Atom shorthand (:short, :medium, :long for common periods)
  """
  @type period_spec :: pos_integer() | :short | :medium | :long

  @doc """
  Checks if a value is a valid OHLCV data point.

  ## Parameters

  - `data` - The value to check

  ## Returns

  - `true` if the value is a valid OHLCV map
  - `false` otherwise

  ## Example

      iex> TradingIndicators.Types.valid_ohlcv?(%{
      ...>   open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"),
      ...>   volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]
      ...> })
      true

      iex> TradingIndicators.Types.valid_ohlcv?(%{close: Decimal.new("100.0")})
      false
  """
  @spec valid_ohlcv?(term()) :: boolean()
  def valid_ohlcv?(%{} = data) do
    required_keys = [:open, :high, :low, :close, :volume, :timestamp]

    Enum.all?(required_keys, &Map.has_key?(data, &1)) and
      Decimal.is_decimal(data.open) and
      Decimal.is_decimal(data.high) and
      Decimal.is_decimal(data.low) and
      Decimal.is_decimal(data.close) and
      is_integer(data.volume) and
      data.volume >= 0 and
      is_struct(data.timestamp, DateTime)
  end

  def valid_ohlcv?(_), do: false

  @doc """
  Checks if a value is a valid indicator result.

  ## Parameters

  - `result` - The value to check

  ## Returns

  - `true` if the value is a valid indicator result map
  - `false` otherwise
  """
  @spec valid_indicator_result?(term()) :: boolean()
  def valid_indicator_result?(%{} = result) do
    Map.has_key?(result, :value) and
      Map.has_key?(result, :timestamp) and
      is_struct(result.timestamp, DateTime) and
      (Decimal.is_decimal(result.value) or is_integer(result.value) or is_map(result.value))
  end

  def valid_indicator_result?(_), do: false

  @doc """
  Converts a period specification to an integer.

  ## Parameters

  - `period_spec` - Period specification (integer or atom)

  ## Returns

  - Integer representation of the period

  ## Example

      iex> TradingIndicators.Types.resolve_period(:short)
      14

      iex> TradingIndicators.Types.resolve_period(20)
      20
  """
  @spec resolve_period(period_spec()) :: pos_integer()
  def resolve_period(:short), do: 14
  def resolve_period(:medium), do: 21
  def resolve_period(:long), do: 50
  def resolve_period(period) when is_integer(period) and period > 0, do: period
end
