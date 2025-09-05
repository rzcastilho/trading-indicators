defmodule TradingIndicators.Trend do
  @moduledoc """
  Trend indicators category module providing unified access to all trend-following indicators.

  This module serves as the main entry point for trend analysis indicators, offering
  both individual indicator access and convenience functions for common operations.

  ## Available Indicators

  - **SMA** - Simple Moving Average  
  - **EMA** - Exponential Moving Average
  - **WMA** - Weighted Moving Average
  - **HMA** - Hull Moving Average  
  - **KAMA** - Kaufman's Adaptive Moving Average
  - **MACD** - Moving Average Convergence Divergence

  ## Usage

      # Direct indicator calculation
      {:ok, sma_results} = TradingIndicators.Trend.calculate(SMA, data, period: 20)
      
      # Using convenience functions
      {:ok, ema_results} = TradingIndicators.Trend.ema(data, period: 12)
      {:ok, macd_results} = TradingIndicators.Trend.macd(data, fast_period: 12, slow_period: 26)
      
      # Get list of available indicators
      indicators = TradingIndicators.Trend.available_indicators()

  ## Streaming Support

  All trend indicators support real-time streaming for live data processing:

      # Initialize streaming state
      state = TradingIndicators.Trend.init_stream(EMA, period: 12)
      
      # Process data points as they arrive
      {:ok, new_state, result} = TradingIndicators.Trend.update_stream(state, data_point)

  ## Common Parameters

  Most trend indicators accept these common parameters:

  - `:period` - Number of periods for calculation
  - `:source` - Price source (`:open`, `:high`, `:low`, `:close`)

  Specific indicators may have additional parameters. See individual indicator
  documentation for complete parameter lists.
  """

  alias TradingIndicators.Trend.{SMA, EMA, WMA, HMA, KAMA, MACD}
  alias TradingIndicators.{Types, Errors}

  @type indicator_module :: SMA | EMA | WMA | HMA | KAMA | MACD

  @doc """
  Returns a list of all available trend indicator modules.

  ## Returns

  - List of indicator modules

  ## Example

      iex> TradingIndicators.Trend.available_indicators()
      [TradingIndicators.Trend.SMA, TradingIndicators.Trend.EMA, 
       TradingIndicators.Trend.WMA, TradingIndicators.Trend.HMA,
       TradingIndicators.Trend.KAMA, TradingIndicators.Trend.MACD]
  """
  @spec available_indicators() :: [indicator_module()]
  def available_indicators, do: [SMA, EMA, WMA, HMA, KAMA, MACD]

  @doc """
  Calculates any trend indicator using a unified interface.

  ## Parameters

  - `indicator` - The indicator module to use
  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Returns

  - `{:ok, results}` - List of indicator calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:ok, results} = TradingIndicators.Trend.calculate(SMA, data, period: 20)
  """
  @spec calculate(indicator_module(), Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(indicator, data, opts \\ []) do
    if indicator in available_indicators() do
      indicator.calculate(data, opts)
    else
      {:error,
       %Errors.InvalidParams{
         message: "Unknown trend indicator: #{inspect(indicator)}",
         param: :indicator,
         value: indicator,
         expected: "one of #{inspect(available_indicators())}"
       }}
    end
  end

  @doc """
  Initializes streaming state for any trend indicator.

  ## Parameters

  - `indicator` - The indicator module to use
  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = TradingIndicators.Trend.init_stream(EMA, period: 12)
  """
  @spec init_stream(indicator_module(), keyword()) :: map()
  def init_stream(indicator, opts \\ []) do
    if indicator in available_indicators() do
      indicator.init_state(opts)
    else
      raise ArgumentError, "Unknown trend indicator: #{inspect(indicator)}"
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

      {:ok, new_state, result} = TradingIndicators.Trend.update_stream(state, data_point)
  """
  @spec update_stream(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_stream(state, data_point) do
    # Try to determine indicator from state metadata or structure
    cond do
      # SMA state
      Map.has_key?(state, :period) and Map.has_key?(state, :prices) and
        Map.has_key?(state, :count) and not Map.has_key?(state, :ema_value) ->
        SMA.update_state(state, data_point)

      # EMA state  
      Map.has_key?(state, :ema_value) and Map.has_key?(state, :smoothing) ->
        EMA.update_state(state, data_point)

      # WMA state
      Map.has_key?(state, :weight_sum) ->
        WMA.update_state(state, data_point)

      # HMA state
      Map.has_key?(state, :wma_half_state) ->
        HMA.update_state(state, data_point)

      # MACD state  
      Map.has_key?(state, :fast_ema_state) ->
        MACD.update_state(state, data_point)

      # KAMA state
      Map.has_key?(state, :kama_value) and Map.has_key?(state, :fast_sc) ->
        KAMA.update_state(state, data_point)

      true ->
        {:error,
         %Errors.StreamStateError{
           message: "Unable to determine indicator type from state",
           operation: :update_stream,
           reason: "unknown state format"
         }}
    end
  end

  # Convenience functions for individual indicators

  @doc """
  Convenience function to calculate Simple Moving Average.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - SMA options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.sma(data, period: 20)
  """
  @spec sma(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def sma(data, opts \\ []), do: SMA.calculate(data, opts)

  @doc """
  Convenience function to calculate Exponential Moving Average.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - EMA options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.ema(data, period: 12)
  """
  @spec ema(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def ema(data, opts \\ []), do: EMA.calculate(data, opts)

  @doc """
  Convenience function to calculate Weighted Moving Average.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - WMA options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.wma(data, period: 10)
  """
  @spec wma(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def wma(data, opts \\ []), do: WMA.calculate(data, opts)

  @doc """
  Convenience function to calculate Hull Moving Average.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - HMA options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.hma(data, period: 14)
  """
  @spec hma(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def hma(data, opts \\ []), do: HMA.calculate(data, opts)

  @doc """
  Convenience function to calculate Kaufman's Adaptive Moving Average.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - KAMA options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.kama(data, period: 10)
  """
  @spec kama(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def kama(data, opts \\ []), do: KAMA.calculate(data, opts)

  @doc """
  Convenience function to calculate Moving Average Convergence Divergence.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - MACD options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Trend.macd(data, fast_period: 12, slow_period: 26, signal_period: 9)
  """
  @spec macd(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def macd(data, opts \\ []), do: MACD.calculate(data, opts)

  @doc """
  Returns information about a specific indicator.

  ## Parameters

  - `indicator` - The indicator module

  ## Returns

  - Map with indicator information

  ## Example

      info = TradingIndicators.Trend.indicator_info(SMA)
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
  Returns information about all available trend indicators.

  ## Returns

  - List of indicator information maps

  ## Example

      all_info = TradingIndicators.Trend.all_indicators_info()
  """
  @spec all_indicators_info() :: [map()]
  def all_indicators_info do
    Enum.map(available_indicators(), &indicator_info/1)
  end
end
