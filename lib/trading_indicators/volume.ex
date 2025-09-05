defmodule TradingIndicators.Volume do
  @moduledoc """
  Volume indicators category module providing unified access to all volume-based analysis indicators.

  This module serves as the main entry point for volume analysis indicators, which
  measure trading activity and money flow patterns. Volume indicators help traders
  assess market participation, confirm price movements, and identify potential
  reversals or continuations.

  ## Available Indicators

  - **OBV** - On-Balance Volume (cumulative volume based on price direction)
  - **VWAP** - Volume Weighted Average Price (price-volume weighted average)
  - **AccumulationDistribution** - Accumulation/Distribution Line (money flow accumulation)
  - **ChaikinMoneyFlow** - Chaikin Money Flow (period-based money flow analysis)

  ## Usage

      # Direct indicator calculation
      {:ok, obv_results} = TradingIndicators.Volume.calculate(OBV, data, [])
      
      # Using convenience functions
      {:ok, vwap_results} = TradingIndicators.Volume.vwap(data, variant: :typical)
      {:ok, ad_results} = TradingIndicators.Volume.accumulation_distribution(data, [])
      {:ok, cmf_results} = TradingIndicators.Volume.chaikin_money_flow(data, period: 20)
      
      # Get list of available indicators
      indicators = TradingIndicators.Volume.available_indicators()

  ## Streaming Support

  All volume indicators support real-time streaming for live data processing:

      # Initialize streaming state
      state = TradingIndicators.Volume.init_stream(OBV, [])
      
      # Process data points as they arrive
      {:ok, new_state, result} = TradingIndicators.Volume.update_stream(state, data_point)

  ## Common Parameters

  Most volume indicators accept these common parameters:

  - `:period` - Number of periods for calculation (for CMF, default: 20)
  - `:variant` - VWAP calculation variant (`:close`, `:typical`, `:weighted`)
  - `:session_reset` - Session reset frequency for VWAP (`:daily`, `:weekly`, `:none`)

  Specific indicators may have additional parameters. See individual indicator
  documentation for complete parameter lists.

  ## Volume Analysis

  Volume indicators help identify:

  - **Price Confirmation** - Volume patterns that confirm price movements
  - **Money Flow** - Direction and strength of institutional money flow
  - **Market Participation** - Level of trader interest and commitment
  - **Support/Resistance** - Volume-based support and resistance levels
  - **Breakout Validation** - Volume confirmation of price breakouts
  - **Trend Strength** - Volume patterns indicating trend continuation or reversal

  ## Volume Data Requirements

  All volume indicators require:

  - Valid OHLCV data with non-negative volume values
  - Volume data as integers (share/contract counts)
  - Proper timestamp ordering for session-based calculations
  - Complete data series without gaps for cumulative indicators

  ## Mathematical Precision

  All calculations use Decimal arithmetic for maximum precision in financial
  calculations, avoiding floating-point precision issues common in trading systems.
  Volume calculations maintain precision for both fractional shares and high-volume
  scenarios.
  """

  alias TradingIndicators.Volume.{OBV, VWAP, AccumulationDistribution, ChaikinMoneyFlow}
  alias TradingIndicators.{Types, Errors}

  @type indicator_module :: OBV | VWAP | AccumulationDistribution | ChaikinMoneyFlow

  @doc """
  Returns a list of all available volume indicator modules.

  ## Returns

  - List of indicator modules

  ## Example

      iex> TradingIndicators.Volume.available_indicators()
      [TradingIndicators.Volume.OBV, TradingIndicators.Volume.VWAP, 
       TradingIndicators.Volume.AccumulationDistribution, TradingIndicators.Volume.ChaikinMoneyFlow]
  """
  @spec available_indicators() :: [indicator_module()]
  def available_indicators, do: [OBV, VWAP, AccumulationDistribution, ChaikinMoneyFlow]

  @doc """
  Calculates any volume indicator using a unified interface.

  ## Parameters

  - `indicator` - The indicator module to use
  - `data` - List of OHLCV data points (volume required for all indicators)
  - `opts` - Calculation options (keyword list)

  ## Returns

  - `{:ok, results}` - List of indicator calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [%{open: Decimal.new("100"), high: Decimal.new("102"), low: Decimal.new("98"), 
                close: Decimal.new("101"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:ok, results} = TradingIndicators.Volume.calculate(OBV, data, [])
  """
  @spec calculate(indicator_module(), Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(indicator, data, opts \\ []) do
    if indicator in available_indicators() do
      indicator.calculate(data, opts)
    else
      {:error,
       %Errors.InvalidParams{
         message: "Unknown volume indicator: #{inspect(indicator)}",
         param: :indicator,
         value: indicator,
         expected: "one of #{inspect(available_indicators())}"
       }}
    end
  end

  @doc """
  Initializes streaming state for any volume indicator.

  ## Parameters

  - `indicator` - The indicator module to use
  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = TradingIndicators.Volume.init_stream(OBV, [])
  """
  @spec init_stream(indicator_module(), keyword()) :: map()
  def init_stream(indicator, opts \\ []) do
    if indicator in available_indicators() do
      indicator.init_state(opts)
    else
      raise ArgumentError, "Unknown volume indicator: #{inspect(indicator)}"
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

      {:ok, new_state, result} = TradingIndicators.Volume.update_stream(state, data_point)
  """
  @spec update_stream(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_stream(state, data_point) do
    # Try to determine indicator from state metadata or structure
    cond do
      # OBV state (has obv_value and previous_close)
      Map.has_key?(state, :obv_value) and Map.has_key?(state, :previous_close) ->
        OBV.update_state(state, data_point)

      # VWAP state (has variant and session settings)  
      Map.has_key?(state, :variant) and Map.has_key?(state, :session_reset) ->
        VWAP.update_state(state, data_point)

      # AccumulationDistribution state (has ad_line_value)
      Map.has_key?(state, :ad_line_value) ->
        AccumulationDistribution.update_state(state, data_point)

      # ChaikinMoneyFlow state (has period and money_flow_volumes)
      Map.has_key?(state, :period) and Map.has_key?(state, :money_flow_volumes) ->
        ChaikinMoneyFlow.update_state(state, data_point)

      true ->
        {:error,
         %Errors.StreamStateError{
           message: "Unable to determine volume indicator type from state",
           operation: :update_stream,
           reason: "unknown state format"
         }}
    end
  end

  # Convenience functions for individual indicators

  @doc """
  Convenience function to calculate On-Balance Volume.

  ## Parameters

  - `data` - List of OHLCV data points (requires close and volume)
  - `opts` - OBV options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volume.obv(data, [])
  """
  @spec obv(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def obv(data, opts \\ []), do: OBV.calculate(data, opts)

  @doc """
  Convenience function to calculate Volume Weighted Average Price.

  ## Parameters

  - `data` - List of OHLCV data points (requires HLCV)
  - `opts` - VWAP options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volume.vwap(data, variant: :typical, session_reset: :daily)
  """
  @spec vwap(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def vwap(data, opts \\ []), do: VWAP.calculate(data, opts)

  @doc """
  Convenience function to calculate Accumulation/Distribution Line.

  ## Parameters

  - `data` - List of OHLCV data points (requires HLCV)
  - `opts` - A/D Line options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volume.accumulation_distribution(data, [])
  """
  @spec accumulation_distribution(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def accumulation_distribution(data, opts \\ []),
    do: AccumulationDistribution.calculate(data, opts)

  @doc """
  Convenience function to calculate Chaikin Money Flow.

  ## Parameters

  - `data` - List of OHLCV data points (requires HLCV)
  - `opts` - CMF options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Volume.chaikin_money_flow(data, period: 20)
  """
  @spec chaikin_money_flow(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def chaikin_money_flow(data, opts \\ []), do: ChaikinMoneyFlow.calculate(data, opts)

  @doc """
  Returns information about a specific volume indicator.

  ## Parameters

  - `indicator` - The indicator module

  ## Returns

  - Map with indicator information

  ## Example

      info = TradingIndicators.Volume.indicator_info(OBV)
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
  Returns information about all available volume indicators.

  ## Returns

  - List of indicator information maps

  ## Example

      all_info = TradingIndicators.Volume.all_indicators_info()
  """
  @spec all_indicators_info() :: [map()]
  def all_indicators_info do
    Enum.map(available_indicators(), &indicator_info/1)
  end
end
