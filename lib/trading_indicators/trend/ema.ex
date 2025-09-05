defmodule TradingIndicators.Trend.EMA do
  @moduledoc """
  Exponential Moving Average (EMA) indicator implementation.

  The Exponential Moving Average gives more weight to recent prices, making it
  more responsive to new information compared to a Simple Moving Average.

  ## Formula

  EMA(t) = (Price(t) × α) + (EMA(t-1) × (1 - α))

  Where:
  - α (alpha) = 2 / (period + 1) is the smoothing factor
  - Price(t) is the current price
  - EMA(t-1) is the previous EMA value

  ## Initialization Methods

  1. **SMA Bootstrap (default)**: Use SMA of first N prices as the initial EMA value
  2. **First Value**: Use the first price as the initial EMA value

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Trend.EMA.calculate(data, period: 3)
      iex> [first | _rest] = result
      iex> Decimal.round(first.value, 2)
      Decimal.new("102.00")

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, must be >= 1)
  - `:source` - Source price field to use (default: `:close`)
  - `:smoothing` - Custom smoothing factor (optional, overrides period-based calculation)
  - `:initialization` - Method to initialize EMA (`:sma_bootstrap` or `:first_value`, default: `:sma_bootstrap`)

  ## Notes

  - More responsive to price changes than SMA
  - Never "forgets" old data completely, but gives exponentially decreasing weights
  - Requires at least `period` number of data points when using SMA bootstrap
  - With `:first_value` initialization, only needs 1 data point to start
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 12
  @precision 6

  @doc """
  Calculates Exponential Moving Average for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:source` - Price source (default: `:close`)
  - `:smoothing` - Custom smoothing factor (optional)
  - `:initialization` - Initialization method (default: `:sma_bootstrap`)

  ## Returns

  - `{:ok, results}` - List of EMA calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = EMA.calculate(data, period: 2)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, :close),
         initialization <- Keyword.get(opts, :initialization, :sma_bootstrap),
         smoothing <- get_smoothing_factor(opts, period),
         :ok <- validate_data_for_initialization(data, period, initialization) do
      prices = extract_prices(data, source)
      calculate_ema_values(prices, period, smoothing, initialization, data)
    end
  end

  @doc """
  Validates parameters for EMA calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)
    smoothing = Keyword.get(opts, :smoothing)
    initialization = Keyword.get(opts, :initialization, :sma_bootstrap)

    with :ok <- validate_period(period),
         :ok <- validate_source(source),
         :ok <- validate_smoothing(smoothing),
         :ok <- validate_initialization(initialization) do
      :ok
    end
  end

  def validate_params(_opts) do
    {:error,
     %Errors.InvalidParams{
       message: "Options must be a keyword list",
       param: :opts,
       value: "non-keyword-list",
       expected: "keyword list"
     }}
  end

  @doc """
  Returns the minimum number of periods required for EMA calculation.

  ## Returns

  - Default period if no options provided
  - 1 if using `:first_value` initialization
  - Configured period if using `:sma_bootstrap`

  ## Example

      iex> TradingIndicators.Trend.EMA.required_periods()
      12
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_period

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods

  ## Example

      iex> TradingIndicators.Trend.EMA.required_periods(period: 14)
      14

      iex> TradingIndicators.Trend.EMA.required_periods(period: 14, initialization: :first_value)
      1
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    initialization = Keyword.get(opts, :initialization, :sma_bootstrap)

    case initialization do
      :first_value -> 1
      :sma_bootstrap -> period
      _ -> period
    end
  end

  @doc """
  Initializes streaming state for real-time EMA calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = EMA.init_state(period: 14, initialization: :first_value)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)
    initialization = Keyword.get(opts, :initialization, :sma_bootstrap)
    smoothing = get_smoothing_factor(opts, period)

    %{
      period: period,
      source: source,
      smoothing: smoothing,
      initialization: initialization,
      prices: [],
      ema_value: nil,
      count: 0,
      initialized: false
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, ema_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = EMA.init_state(period: 3)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = EMA.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          source: source,
          smoothing: smoothing,
          initialization: initialization,
          prices: prices,
          ema_value: ema_value,
          count: count,
          initialized: initialized
        } = _state,
        data_point
      ) do
    try do
      price = extract_single_price(data_point, source)
      new_count = count + 1
      new_prices = update_price_buffer(prices, price, period, initialization)

      case calculate_next_ema(
             price,
             ema_value,
             smoothing,
             initialization,
             new_prices,
             period,
             initialized
           ) do
        # EMA calculated and initialized
        {new_ema, true} ->
          timestamp = get_timestamp(data_point)

          result = %{
            value: Decimal.round(new_ema, @precision),
            timestamp: timestamp,
            metadata: %{
              indicator: "EMA",
              period: period,
              source: source,
              smoothing: smoothing
            }
          }

          new_state = %{
            period: period,
            source: source,
            smoothing: smoothing,
            initialization: initialization,
            prices: new_prices,
            ema_value: new_ema,
            count: new_count,
            initialized: true
          }

          {:ok, new_state, result}

        # Not enough data yet
        nil ->
          new_state = %{
            period: period,
            source: source,
            smoothing: smoothing,
            initialization: initialization,
            prices: new_prices,
            ema_value: ema_value,
            count: new_count,
            initialized: initialized
          }

          {:ok, new_state, nil}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for EMA streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
  end

  defp validate_source(source) when source in [:open, :high, :low, :close], do: :ok

  defp validate_source(source) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid source: #{inspect(source)}",
       param: :source,
       value: source,
       expected: "one of [:open, :high, :low, :close]"
     }}
  end

  defp validate_smoothing(nil), do: :ok

  defp validate_smoothing(smoothing) when Decimal.is_decimal(smoothing) do
    if Decimal.gt?(smoothing, Decimal.new("0")) and Decimal.lte?(smoothing, Decimal.new("1")) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         message: "Smoothing factor must be between 0 and 1, got #{Decimal.to_string(smoothing)}",
         param: :smoothing,
         value: smoothing,
         expected: "decimal between 0 and 1"
       }}
    end
  end

  defp validate_smoothing(smoothing) when is_number(smoothing) do
    validate_smoothing(Decimal.new(smoothing))
  end

  defp validate_smoothing(smoothing) do
    {:error,
     %Errors.InvalidParams{
       message: "Smoothing factor must be a decimal, got #{inspect(smoothing)}",
       param: :smoothing,
       value: smoothing,
       expected: "decimal"
     }}
  end

  defp validate_initialization(init) when init in [:sma_bootstrap, :first_value], do: :ok

  defp validate_initialization(init) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid initialization method: #{inspect(init)}",
       param: :initialization,
       value: init,
       expected: "one of [:sma_bootstrap, :first_value]"
     }}
  end

  defp validate_data_for_initialization(data, period, :sma_bootstrap) do
    Utils.validate_data_length(data, period)
  end

  defp validate_data_for_initialization(data, _period, :first_value) do
    Utils.validate_data_length(data, 1)
  end

  defp get_smoothing_factor(opts, period) do
    case Keyword.get(opts, :smoothing) do
      nil ->
        # Standard EMA smoothing: 2 / (period + 1)
        Decimal.div(Decimal.new("2"), Decimal.new(period + 1))

      custom_smoothing when is_number(custom_smoothing) ->
        Decimal.new(custom_smoothing)

      custom_smoothing when Decimal.is_decimal(custom_smoothing) ->
        custom_smoothing
    end
  end

  defp extract_prices(data, source) when is_list(data) and length(data) > 0 do
    # Check if data is already a price series (list of decimals)
    case List.first(data) do
      # Already a price series
      %Decimal{} -> data
      # OHLCV data
      %{} = _ohlcv -> extract_ohlcv_prices(data, source)
      # Assume it's some other price series format
      _ -> data
    end
  end

  defp extract_ohlcv_prices(data, :close), do: Utils.extract_closes(data)
  defp extract_ohlcv_prices(data, :open), do: Utils.extract_opens(data)
  defp extract_ohlcv_prices(data, :high), do: Utils.extract_highs(data)
  defp extract_ohlcv_prices(data, :low), do: Utils.extract_lows(data)

  defp extract_single_price(%{} = data_point, source) do
    Map.fetch!(data_point, source)
  end

  defp extract_single_price(price, _source) when Decimal.is_decimal(price) do
    price
  end

  defp extract_single_price(price, _source) when is_number(price) do
    Decimal.new(price)
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_ema_values(prices, period, smoothing, initialization, original_data) do
    case initialization do
      :first_value ->
        calculate_ema_first_value(prices, smoothing, original_data, period)

      :sma_bootstrap ->
        calculate_ema_sma_bootstrap(prices, period, smoothing, original_data)
    end
  end

  defp calculate_ema_first_value([first_price | rest_prices], smoothing, original_data, period) do
    {results, _final_ema} =
      rest_prices
      |> Enum.with_index(1)
      |> Enum.reduce({[], first_price}, fn {price, index}, {acc, prev_ema} ->
        new_ema = calculate_ema_step(price, prev_ema, smoothing)
        timestamp = get_data_timestamp(original_data, index)

        result = %{
          value: Decimal.round(new_ema, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "EMA",
            period: period,
            source: :close,
            smoothing: smoothing
          }
        }

        {[result | acc], new_ema}
      end)

    # Add the first EMA value (which is just the first price)
    first_timestamp = get_data_timestamp(original_data, 0)

    first_result = %{
      value: Decimal.round(first_price, @precision),
      timestamp: first_timestamp,
      metadata: %{
        indicator: "EMA",
        period: period,
        source: :close,
        smoothing: smoothing
      }
    }

    all_results = [first_result | Enum.reverse(results)]
    {:ok, all_results}
  end

  defp calculate_ema_sma_bootstrap(prices, period, smoothing, original_data) do
    # Calculate initial SMA
    sma_prices = Enum.take(prices, period)
    initial_ema = Utils.mean(sma_prices)

    # Calculate EMA for remaining prices
    remaining_prices = Enum.drop(prices, period)

    {results, _final_ema} =
      remaining_prices
      |> Enum.with_index(period)
      |> Enum.reduce({[], initial_ema}, fn {price, index}, {acc, prev_ema} ->
        new_ema = calculate_ema_step(price, prev_ema, smoothing)
        timestamp = get_data_timestamp(original_data, index)

        result = %{
          value: Decimal.round(new_ema, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "EMA",
            period: period,
            source: :close,
            smoothing: smoothing
          }
        }

        {[result | acc], new_ema}
      end)

    # Add the initial EMA value (SMA bootstrap)
    initial_timestamp = get_data_timestamp(original_data, period - 1)

    initial_result = %{
      value: Decimal.round(initial_ema, @precision),
      timestamp: initial_timestamp,
      metadata: %{
        indicator: "EMA",
        period: period,
        source: :close,
        smoothing: smoothing
      }
    }

    all_results = [initial_result | Enum.reverse(results)]
    {:ok, all_results}
  end

  defp calculate_ema_step(price, prev_ema, smoothing) do
    # EMA = (Price × α) + (PrevEMA × (1 - α))
    price_component = Decimal.mult(price, smoothing)
    ema_component = Decimal.mult(prev_ema, Decimal.sub(Decimal.new("1"), smoothing))
    Decimal.add(price_component, ema_component)
  end

  defp get_data_timestamp(data, index) when is_list(data) do
    if index < length(data) do
      case Enum.at(data, index) do
        %{timestamp: timestamp} -> timestamp
        # For price series without timestamps
        _ -> DateTime.utc_now()
      end
    else
      DateTime.utc_now()
    end
  end

  defp update_price_buffer(prices, new_price, period, initialization) do
    updated_prices = prices ++ [new_price]

    case initialization do
      :first_value ->
        # For first value init, we don't need a buffer
        [new_price]

      :sma_bootstrap ->
        # For SMA bootstrap, maintain a buffer up to period size
        if length(updated_prices) > period do
          Enum.take(updated_prices, -period)
        else
          updated_prices
        end
    end
  end

  defp calculate_next_ema(price, nil, _smoothing, :first_value, _prices, _period, false) do
    # First value initialization - first price becomes first EMA
    {price, true}
  end

  defp calculate_next_ema(price, prev_ema, smoothing, :first_value, _prices, _period, true) do
    # Continue EMA calculation with first value method
    new_ema = calculate_ema_step(price, prev_ema, smoothing)
    {new_ema, true}
  end

  defp calculate_next_ema(_price, nil, _smoothing, :sma_bootstrap, prices, period, false) do
    # SMA bootstrap - need enough prices first
    if length(prices) >= period do
      # Calculate initial SMA
      initial_ema = Utils.mean(prices)
      {initial_ema, true}
    else
      # Not enough data yet
      nil
    end
  end

  defp calculate_next_ema(price, prev_ema, smoothing, :sma_bootstrap, _prices, _period, true) do
    # Continue EMA calculation with SMA bootstrap method
    new_ema = calculate_ema_step(price, prev_ema, smoothing)
    {new_ema, true}
  end
end
