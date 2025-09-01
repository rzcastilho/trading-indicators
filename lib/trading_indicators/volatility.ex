defmodule TradingIndicators.Volatility do
  @moduledoc """
  Volatility indicators category module providing unified access to all volatility measures.

  This module serves as the main entry point for volatility analysis indicators, which
  measure the degree of variation in price movements over time. Volatility indicators
  help traders assess market uncertainty, risk levels, and potential price ranges.

  ## Available Indicators

  - **StandardDeviation** - Standard deviation of price movements (sample/population)
  - **ATR** - Average True Range (Wilder's volatility measure)  
  - **BollingerBands** - Price channels with %B and bandwidth calculations
  - **VolatilityIndex** - Historical and advanced volatility estimators

  ## Usage

      # Direct indicator calculation
      {:ok, stddev_results} = TradingIndicators.Volatility.calculate(StandardDeviation, data, period: 20)
      
      # Using convenience functions
      {:ok, atr_results} = TradingIndicators.Volatility.atr(data, period: 14, smoothing: :rma)
      {:ok, bb_results} = TradingIndicators.Volatility.bollinger_bands(data, period: 20, multiplier: 2.0)
      
      # Get list of available indicators
      indicators = TradingIndicators.Volatility.available_indicators()

  ## Streaming Support

  All volatility indicators support real-time streaming for live data processing:

      # Initialize streaming state
      state = TradingIndicators.Volatility.init_stream(ATR, period: 14, smoothing: :rma)
      
      # Process data points as they arrive
      {:ok, new_state, result} = TradingIndicators.Volatility.update_stream(state, data_point)

  ## Common Parameters

  Most volatility indicators accept these common parameters:

  - `:period` - Number of periods for calculation (default varies by indicator)
  - `:source` - Price source (`:open`, `:high`, `:low`, `:close`) (where applicable)
  - `:smoothing` - Smoothing method for ATR (`:sma`, `:ema`, `:rma`)
  - `:multiplier` - Standard deviation multiplier for Bollinger Bands
  - `:calculation` - Sample vs population calculation for Standard Deviation
  
  Specific indicators may have additional parameters. See individual indicator
  documentation for complete parameter lists.

  ## Volatility Analysis

  Volatility indicators help identify:

  - **Market Uncertainty** - Higher volatility indicates more uncertain conditions
  - **Risk Assessment** - Volatility levels inform position sizing and risk management
  - **Breakout Potential** - Low volatility often precedes significant moves
  - **Support/Resistance** - Bollinger Bands provide dynamic price levels
  - **Entry/Exit Timing** - Volatility expansion/contraction cycles

  ## Mathematical Precision

  All calculations use Decimal arithmetic for maximum precision in financial
  calculations, avoiding floating-point precision issues common in trading systems.
  """

  alias TradingIndicators.Volatility.{StandardDeviation, ATR, BollingerBands, VolatilityIndex}
  alias TradingIndicators.{Types, Errors}

  @type indicator_module :: StandardDeviation | ATR | BollingerBands | VolatilityIndex

  @doc """
  Returns a list of all available volatility indicator modules.

  ## Returns

  - List of indicator modules

  ## Example

      iex> TradingIndicators.Volatility.available_indicators()
      [TradingIndicators.Volatility.StandardDeviation, TradingIndicators.Volatility.ATR, 
       TradingIndicators.Volatility.BollingerBands, TradingIndicators.Volatility.VolatilityIndex]
  """
  @spec available_indicators() :: [indicator_module()]
  def available_indicators, do: [StandardDeviation, ATR, BollingerBands, VolatilityIndex]

  @doc """
  Calculates any volatility indicator using a unified interface.

  ## Parameters

  - `indicator` - The indicator module to use
  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Returns

  - `{:ok, results}` - List of indicator calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [%{close: Decimal.new("100"), high: Decimal.new("102"), low: Decimal.new("98"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:ok, results} = TradingIndicators.Volatility.calculate(StandardDeviation, data, period: 20)
  """
  @spec calculate(indicator_module(), Types.data_series() | [Decimal.t()], keyword()) ::
    {:ok, Types.result_series()} | {:error, term()}
  def calculate(indicator, data, opts \\ []) do
    if indicator in available_indicators() do
      indicator.calculate(data, opts)
    else
      {:error, %Errors.InvalidParams{
        message: "Unknown volatility indicator: #{inspect(indicator)}",
        param: :indicator,
        value: indicator,
        expected: "one of #{inspect(available_indicators())}"
      }}
    end
  end

  @doc """
  Initializes streaming state for any volatility indicator.

  ## Parameters

  - `indicator` - The indicator module to use
  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = TradingIndicators.Volatility.init_stream(ATR, period: 14)
  """
  @spec init_stream(indicator_module(), keyword()) :: map()
  def init_stream(indicator, opts \\ []) do
    if indicator in available_indicators() do
      indicator.init_state(opts)
    else
      raise ArgumentError, "Unknown volatility indicator: #{inspect(indicator)}"
    end
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state (must contain indicator info)
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      {:ok, new_state, result} = TradingIndicators.Volatility.update_stream(state, data_point)
  """
  @spec update_stream(map(), Types.ohlcv() | Decimal.t()) :: 
    {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_stream(state, data_point) do
    # Try to determine indicator from state metadata or structure
    cond do
      # StandardDeviation state (has prices and calculation type)
      Map.has_key?(state, :calculation) and Map.has_key?(state, :prices) ->
        StandardDeviation.update_state(state, data_point)
      
      # ATR state (has smoothing and true_ranges/atr_value)  
      Map.has_key?(state, :smoothing) and Map.has_key?(state, :atr_value) ->
        ATR.update_state(state, data_point)
      
      # BollingerBands state (has multiplier and prices)
      Map.has_key?(state, :multiplier) and Map.has_key?(state, :prices) ->
        BollingerBands.update_state(state, data_point)
        
      # VolatilityIndex state (has method and data_points)
      Map.has_key?(state, :method) and Map.has_key?(state, :data_points) ->
        VolatilityIndex.update_state(state, data_point)
      
      true ->
        {:error, %Errors.StreamStateError{
          message: "Unable to determine volatility indicator type from state",
          operation: :update_stream,
          reason: "unknown state format"
        }}
    end
  end

  # Convenience functions for individual indicators

  @doc """
  Convenience function to calculate Standard Deviation.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Standard Deviation options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volatility.standard_deviation(data, period: 20, calculation: :sample)
  """
  @spec standard_deviation(Types.data_series() | [Decimal.t()], keyword()) :: 
    {:ok, Types.result_series()} | {:error, term()}
  def standard_deviation(data, opts \\ []), do: StandardDeviation.calculate(data, opts)

  @doc """
  Convenience function to calculate Average True Range.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - ATR options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volatility.atr(data, period: 14, smoothing: :rma)
  """
  @spec atr(Types.data_series(), keyword()) :: 
    {:ok, Types.result_series()} | {:error, term()}
  def atr(data, opts \\ []), do: ATR.calculate(data, opts)

  @doc """
  Convenience function to calculate Bollinger Bands.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Bollinger Bands options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volatility.bollinger_bands(data, period: 20, multiplier: 2.0)
  """
  @spec bollinger_bands(Types.data_series() | [Decimal.t()], keyword()) :: 
    {:ok, [Types.bollinger_result()]} | {:error, term()}
  def bollinger_bands(data, opts \\ []), do: BollingerBands.calculate(data, opts)

  @doc """
  Convenience function to calculate Volatility Index.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Volatility Index options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volatility.volatility_index(data, period: 20, method: :historical)
  """
  @spec volatility_index(Types.data_series() | [Decimal.t()], keyword()) :: 
    {:ok, Types.result_series()} | {:error, term()}
  def volatility_index(data, opts \\ []), do: VolatilityIndex.calculate(data, opts)

  @doc """
  Returns information about a specific volatility indicator.

  ## Parameters

  - `indicator` - The indicator module

  ## Returns

  - Map with indicator information

  ## Example

      info = TradingIndicators.Volatility.indicator_info(StandardDeviation)
  """
  @spec indicator_info(indicator_module()) :: map()
  def indicator_info(indicator) do
    if indicator in available_indicators() do
      %{
        module: indicator,
        name: indicator |> Module.split() |> List.last(),
        required_periods: indicator.required_periods(),
        supports_streaming: function_exported?(indicator, :init_state, 1)
      }
    else
      %{error: "Unknown indicator"}
    end
  end

  @doc """
  Returns information about all available volatility indicators.

  ## Returns

  - List of indicator information maps

  ## Example

      all_info = TradingIndicators.Volatility.all_indicators_info()
  """
  @spec all_indicators_info() :: [map()]
  def all_indicators_info do
    Enum.map(available_indicators(), &indicator_info/1)
  end
end