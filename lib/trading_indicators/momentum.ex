defmodule TradingIndicators.Momentum do
  @moduledoc """
  Momentum indicators category module providing unified access to all momentum oscillators.

  This module serves as the main entry point for momentum analysis indicators, which
  measure the speed and magnitude of price changes to identify potential trend reversals
  and overbought/oversold conditions.

  ## Available Indicators

  - **RSI** - Relative Strength Index (14-period oscillator: 0-100)
  - **Stochastic** - Stochastic Oscillator (%K and %D lines)  
  - **WilliamsR** - Williams %R (inverted stochastic: -100 to 0)
  - **CCI** - Commodity Channel Index (typical price oscillator)
  - **ROC** - Rate of Change (percentage/price change momentum)
  - **Momentum** - Price Momentum oscillator

  ## Usage

      # Direct indicator calculation
      {:ok, rsi_results} = TradingIndicators.Momentum.calculate(RSI, data, period: 14)
      
      # Using convenience functions
      {:ok, stoch_results} = TradingIndicators.Momentum.stochastic(data, k_period: 14)
      {:ok, williams_results} = TradingIndicators.Momentum.williams_r(data, period: 14)
      
      # Get list of available indicators
      indicators = TradingIndicators.Momentum.available_indicators()

  ## Streaming Support

  All momentum indicators support real-time streaming for live data processing:

      # Initialize streaming state
      state = TradingIndicators.Momentum.init_stream(RSI, period: 14)
      
      # Process data points as they arrive
      {:ok, new_state, result} = TradingIndicators.Momentum.update_stream(state, data_point)

  ## Common Parameters

  Most momentum indicators accept these common parameters:

  - `:period` - Number of periods for calculation (default varies by indicator)
  - `:source` - Price source (`:open`, `:high`, `:low`, `:close`)
  - `:overbought` - Overbought threshold level (RSI, Stochastic, Williams %R)
  - `:oversold` - Oversold threshold level (RSI, Stochastic, Williams %R)

  Specific indicators may have additional parameters. See individual indicator
  documentation for complete parameter lists.

  ## Momentum Analysis

  Momentum indicators help identify:

  - **Trend Strength** - How strong the current trend is
  - **Overbought/Oversold Conditions** - When prices may be due for reversal
  - **Divergences** - When price and momentum move in opposite directions
  - **Entry/Exit Signals** - Potential buy/sell opportunities

  ## Mathematical Precision

  All calculations use Decimal arithmetic for maximum precision in financial
  calculations, avoiding floating-point precision issues common in trading systems.
  """

  alias TradingIndicators.Momentum.{RSI, Stochastic, WilliamsR, CCI, ROC}
  alias TradingIndicators.Momentum.Momentum, as: MomentumIndicator
  alias TradingIndicators.{Types, Errors}

  @type indicator_module :: RSI | Stochastic | WilliamsR | CCI | ROC | MomentumIndicator

  @doc """
  Returns a list of all available momentum indicator modules.

  ## Returns

  - List of indicator modules

  ## Example

      iex> TradingIndicators.Momentum.available_indicators()
      [TradingIndicators.Momentum.RSI, TradingIndicators.Momentum.Stochastic, 
       TradingIndicators.Momentum.WilliamsR, TradingIndicators.Momentum.CCI,
       TradingIndicators.Momentum.ROC, TradingIndicators.Momentum.Momentum]
  """
  @spec available_indicators() :: [indicator_module()]
  def available_indicators, do: [RSI, Stochastic, WilliamsR, CCI, ROC, MomentumIndicator]

  @doc """
  Calculates any momentum indicator using a unified interface.

  ## Parameters

  - `indicator` - The indicator module to use
  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Returns

  - `{:ok, results}` - List of indicator calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [%{close: Decimal.new("100"), high: Decimal.new("102"), low: Decimal.new("98"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:ok, results} = TradingIndicators.Momentum.calculate(RSI, data, period: 14)
  """
  @spec calculate(indicator_module(), Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(indicator, data, opts \\ []) do
    if indicator in available_indicators() do
      indicator.calculate(data, opts)
    else
      {:error,
       %Errors.InvalidParams{
         message: "Unknown momentum indicator: #{inspect(indicator)}",
         param: :indicator,
         value: indicator,
         expected: "one of #{inspect(available_indicators())}"
       }}
    end
  end

  @doc """
  Initializes streaming state for any momentum indicator.

  ## Parameters

  - `indicator` - The indicator module to use
  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = TradingIndicators.Momentum.init_stream(RSI, period: 14)
  """
  @spec init_stream(indicator_module(), keyword()) :: map()
  def init_stream(indicator, opts \\ []) do
    if indicator in available_indicators() do
      indicator.init_state(opts)
    else
      raise ArgumentError, "Unknown momentum indicator: #{inspect(indicator)}"
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

      {:ok, new_state, result} = TradingIndicators.Momentum.update_stream(state, data_point)
  """
  @spec update_stream(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_stream(state, data_point) do
    # Try to determine indicator from state metadata or structure
    cond do
      # RSI state (has gains, losses, avg_gain, avg_loss)
      Map.has_key?(state, :avg_gain) and Map.has_key?(state, :avg_loss) ->
        RSI.update_state(state, data_point)

      # Stochastic state (has k_period, d_period, k_values)  
      Map.has_key?(state, :k_period) and Map.has_key?(state, :k_values) ->
        Stochastic.update_state(state, data_point)

      # Williams %R state (has period and recent highs/lows)
      Map.has_key?(state, :recent_highs) and Map.has_key?(state, :recent_lows) ->
        WilliamsR.update_state(state, data_point)

      # CCI state (has typical_prices and moving_averages)
      Map.has_key?(state, :typical_prices) and Map.has_key?(state, :mean_deviations) ->
        CCI.update_state(state, data_point)

      # ROC state (has historical_prices)
      Map.has_key?(state, :historical_prices) and Map.has_key?(state, :roc_period) ->
        ROC.update_state(state, data_point)

      # Momentum state (has previous_prices and momentum_period)
      Map.has_key?(state, :previous_prices) and Map.has_key?(state, :momentum_period) ->
        MomentumIndicator.update_state(state, data_point)

      true ->
        {:error,
         %Errors.StreamStateError{
           message: "Unable to determine momentum indicator type from state",
           operation: :update_stream,
           reason: "unknown state format"
         }}
    end
  end

  # Convenience functions for individual indicators

  @doc """
  Convenience function to calculate Relative Strength Index.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - RSI options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.rsi(data, period: 14)
  """
  @spec rsi(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def rsi(data, opts \\ []), do: RSI.calculate(data, opts)

  @doc """
  Convenience function to calculate Stochastic Oscillator.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Stochastic options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.stochastic(data, k_period: 14, d_period: 3)
  """
  @spec stochastic(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def stochastic(data, opts \\ []), do: Stochastic.calculate(data, opts)

  @doc """
  Convenience function to calculate Williams %R.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Williams %R options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.williams_r(data, period: 14)
  """
  @spec williams_r(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def williams_r(data, opts \\ []), do: WilliamsR.calculate(data, opts)

  @doc """
  Convenience function to calculate Commodity Channel Index.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - CCI options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.cci(data, period: 20)
  """
  @spec cci(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def cci(data, opts \\ []), do: CCI.calculate(data, opts)

  @doc """
  Convenience function to calculate Rate of Change.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - ROC options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.roc(data, period: 12)
  """
  @spec roc(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def roc(data, opts \\ []), do: ROC.calculate(data, opts)

  @doc """
  Convenience function to calculate Momentum oscillator.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Momentum options (keyword list)

  ## Example

      {:ok, results} = TradingIndicators.Momentum.momentum(data, period: 10)
  """
  @spec momentum(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def momentum(data, opts \\ []), do: MomentumIndicator.calculate(data, opts)

  @doc """
  Returns information about a specific momentum indicator.

  ## Parameters

  - `indicator` - The indicator module

  ## Returns

  - Map with indicator information

  ## Example

      info = TradingIndicators.Momentum.indicator_info(RSI)
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
  Returns information about all available momentum indicators.

  ## Returns

  - List of indicator information maps

  ## Example

      all_info = TradingIndicators.Momentum.all_indicators_info()
  """
  @spec all_indicators_info() :: [map()]
  def all_indicators_info do
    Enum.map(available_indicators(), &indicator_info/1)
  end
end
