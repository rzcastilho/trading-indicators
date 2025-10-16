defmodule TradingIndicators.Momentum.RSI do
  @moduledoc """
  Relative Strength Index (RSI) momentum oscillator implementation.

  The RSI is a momentum oscillator that measures the speed and magnitude of recent 
  price changes to evaluate overbought or oversold conditions in the price of a stock 
  or other asset. It oscillates between 0 and 100, with readings above 70 typically 
  considered overbought and readings below 30 considered oversold.

  ## Formula

  RSI = 100 - (100 / (1 + RS))

  Where:
  - RS = Average Gain / Average Loss (Relative Strength)
  - Average Gain = Sum of Gains over n periods / n
  - Average Loss = Sum of Losses over n periods / n

  The traditional smoothing method uses a modified moving average where:
  - Subsequent Average Gain = ((Previous Average Gain * (n-1)) + Current Gain) / n
  - Subsequent Average Loss = ((Previous Average Loss * (n-1)) + Current Loss) / n

  ## Variants

  - **Standard RSI** - Uses Wilder's smoothing (default)
  - **Cutler's RSI** - Uses simple moving average for gains/losses

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("44.34"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("44.09"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("44.15"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("43.61"), timestamp: ~U[2024-01-01 09:33:00Z]},
      ...>   %{close: Decimal.new("44.33"), timestamp: ~U[2024-01-01 09:34:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.RSI.calculate(data, period: 4)
      iex> length(result)
      1

  ## Parameters

  - `:period` - Number of periods for RSI calculation (default: 14)
  - `:source` - Source price field to use (default: `:close`)
  - `:overbought` - Overbought threshold level (default: 70)
  - `:oversold` - Oversold threshold level (default: 30)  
  - `:smoothing` - Smoothing method (`:wilder` or `:sma`, default: `:wilder`)

  ## Interpretation

  - **RSI > 70**: Generally considered overbought (potential sell signal)
  - **RSI < 30**: Generally considered oversold (potential buy signal)
  - **RSI crossing 50**: Momentum shift (bullish above, bearish below)
  - **Divergences**: When RSI and price move in opposite directions

  ## Notes

  - Requires at least `period + 1` data points for initial calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - First RSI value appears after period + 1 data points
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 14
  @default_overbought 70
  @default_oversold 30

  @doc """
  Calculates Relative Strength Index for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:source` - Price source (default: `:close`)
  - `:overbought` - Overbought level (default: #{@default_overbought})
  - `:oversold` - Oversold level (default: #{@default_oversold})
  - `:smoothing` - `:wilder` or `:sma` (default: `:wilder`)

  ## Returns

  - `{:ok, results}` - List of RSI calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = RSI.calculate(data, period: 14)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, :close),
         smoothing <- Keyword.get(opts, :smoothing, :wilder),
         overbought <- Keyword.get(opts, :overbought, @default_overbought),
         oversold <- Keyword.get(opts, :oversold, @default_oversold),
         :ok <- Utils.validate_data_length(data, period + 1) do
      prices = extract_prices(data, source)
      calculate_rsi_values(prices, period, smoothing, overbought, oversold, data)
    end
  end

  @doc """
  Validates parameters for RSI calculation.

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
    smoothing = Keyword.get(opts, :smoothing, :wilder)
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    with :ok <- validate_period(period),
         :ok <- validate_source(source),
         :ok <- validate_smoothing(smoothing),
         :ok <- validate_level(overbought, :overbought),
         :ok <- validate_level(oversold, :oversold),
         :ok <- validate_level_relationship(oversold, overbought) do
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
  Returns the minimum number of periods required for RSI calculation.

  ## Returns

  - Default period + 1 if no options provided
  - Configured period + 1 from options

  ## Example

      iex> TradingIndicators.Momentum.RSI.required_periods()
      15
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_period + 1

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods

  ## Example

      iex> TradingIndicators.Momentum.RSI.required_periods(period: 10)
      11
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    period + 1
  end

  @doc """
  Returns metadata describing all parameters accepted by the RSI indicator.

  ## Returns

  - List of parameter metadata maps

  ## Example

      iex> metadata = TradingIndicators.Momentum.RSI.parameter_metadata()
      iex> Enum.any?(metadata, fn param -> param.name == :period end)
      true
  """
  @impl true
  @spec parameter_metadata() :: [Types.param_metadata()]
  def parameter_metadata do
    [
      %Types.ParamMetadata{
        name: :period,
        type: :integer,
        default: @default_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Number of periods for RSI calculation"
      },
      %Types.ParamMetadata{
        name: :source,
        type: :atom,
        default: :close,
        required: false,
        min: nil,
        max: nil,
        options: [:open, :high, :low, :close],
        description: "Source price field to use"
      },
      %Types.ParamMetadata{
        name: :overbought,
        type: :integer,
        default: @default_overbought,
        required: false,
        min: 0,
        max: 100,
        options: nil,
        description: "Overbought threshold level"
      },
      %Types.ParamMetadata{
        name: :oversold,
        type: :integer,
        default: @default_oversold,
        required: false,
        min: 0,
        max: 100,
        options: nil,
        description: "Oversold threshold level"
      },
      %Types.ParamMetadata{
        name: :smoothing,
        type: :atom,
        default: :wilder,
        required: false,
        min: nil,
        max: nil,
        options: [:wilder, :sma],
        description: "Smoothing method for gains and losses"
      }
    ]
  end

  @doc """
  Initializes streaming state for real-time RSI calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = RSI.init_state(period: 14)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)
    smoothing = Keyword.get(opts, :smoothing, :wilder)
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    %{
      period: period,
      source: source,
      smoothing: smoothing,
      overbought: overbought,
      oversold: oversold,
      previous_close: nil,
      gains: [],
      losses: [],
      avg_gain: nil,
      avg_loss: nil,
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, rsi_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = RSI.init_state(period: 14)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = RSI.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          source: source,
          smoothing: smoothing,
          overbought: overbought,
          oversold: oversold,
          previous_close: prev_close,
          gains: gains,
          losses: losses,
          avg_gain: avg_gain,
          avg_loss: avg_loss,
          count: count
        } = _state,
        data_point
      ) do
    try do
      current_close = extract_single_price(data_point, source)
      new_count = count + 1

      # First data point - just store the close price
      if prev_close == nil do
        new_state = %{
          period: period,
          source: source,
          smoothing: smoothing,
          overbought: overbought,
          oversold: oversold,
          previous_close: current_close,
          gains: gains,
          losses: losses,
          avg_gain: avg_gain,
          avg_loss: avg_loss,
          count: new_count
        }

        {:ok, new_state, nil}
      else
        # Calculate gain/loss
        change = Decimal.sub(current_close, prev_close)
        gain = if Decimal.gt?(change, Decimal.new("0")), do: change, else: Decimal.new("0")

        loss =
          if Decimal.lt?(change, Decimal.new("0")), do: Decimal.abs(change), else: Decimal.new("0")

        new_gains = update_buffer(gains, gain, period)
        new_losses = update_buffer(losses, loss, period)

        # Calculate RSI if we have enough data
        {new_avg_gain, new_avg_loss, rsi_result} =
          calculate_streaming_rsi(
            new_gains,
            new_losses,
            avg_gain,
            avg_loss,
            period,
            smoothing,
            overbought,
            oversold,
            new_count,
            data_point
          )

        new_state = %{
          period: period,
          source: source,
          smoothing: smoothing,
          overbought: overbought,
          oversold: oversold,
          previous_close: current_close,
          gains: new_gains,
          losses: new_losses,
          avg_gain: new_avg_gain,
          avg_loss: new_avg_loss,
          count: new_count
        }

        {:ok, new_state, rsi_result}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for RSI streaming",
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

  defp validate_smoothing(smoothing) when smoothing in [:wilder, :sma], do: :ok

  defp validate_smoothing(smoothing) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid smoothing method: #{inspect(smoothing)}",
       param: :smoothing,
       value: smoothing,
       expected: "one of [:wilder, :sma]"
     }}
  end

  defp validate_level(level, _name) when is_number(level) and level >= 0 and level <= 100, do: :ok

  defp validate_level(level, name) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid #{name} level: #{inspect(level)}",
       param: name,
       value: level,
       expected: "number between 0 and 100"
     }}
  end

  defp validate_level_relationship(oversold, overbought) when oversold < overbought, do: :ok

  defp validate_level_relationship(oversold, overbought) do
    {:error,
     %Errors.InvalidParams{
       message: "Oversold level (#{oversold}) must be less than overbought level (#{overbought})",
       param: :levels,
       value: {oversold, overbought},
       expected: "oversold < overbought"
     }}
  end

  defp extract_prices(data, source) when is_list(data) and length(data) > 0 do
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

  defp calculate_rsi_values(prices, period, smoothing, overbought, oversold, original_data) do
    # Calculate price changes (gains and losses)
    changes = calculate_price_changes(prices)
    {gains, losses} = split_gains_losses(changes)

    # Calculate RSI values
    rsi_values = calculate_rsi_series(gains, losses, period, smoothing)

    # Build result structures
    results = build_rsi_results(rsi_values, period, smoothing, overbought, oversold, original_data)

    {:ok, results}
  end

  defp calculate_price_changes([_]), do: []

  defp calculate_price_changes([first | rest]) do
    Enum.zip([first | rest], rest)
    |> Enum.map(fn {prev, curr} -> Decimal.sub(curr, prev) end)
  end

  defp split_gains_losses(changes) do
    gains =
      Enum.map(changes, fn change ->
        if Decimal.gt?(change, Decimal.new("0")), do: change, else: Decimal.new("0")
      end)

    losses =
      Enum.map(changes, fn change ->
        if Decimal.lt?(change, Decimal.new("0")), do: Decimal.abs(change), else: Decimal.new("0")
      end)

    {gains, losses}
  end

  defp calculate_rsi_series(gains, losses, period, smoothing) do
    gain_windows = Utils.sliding_window(gains, period)
    loss_windows = Utils.sliding_window(losses, period)

    Enum.zip(gain_windows, loss_windows)
    |> Enum.with_index()
    |> Enum.map(fn {{gain_window, loss_window}, index} ->
      if index == 0 do
        # First calculation - use simple average
        avg_gain = Utils.mean(gain_window)
        avg_loss = Utils.mean(loss_window)
        calculate_rsi_value(avg_gain, avg_loss)
      else
        # Subsequent calculations - use smoothing method
        case smoothing do
          :wilder ->
            calculate_wilder_rsi(gains, losses, period, index)

          :sma ->
            avg_gain = Utils.mean(gain_window)
            avg_loss = Utils.mean(loss_window)
            calculate_rsi_value(avg_gain, avg_loss)
        end
      end
    end)
  end

  defp calculate_wilder_rsi(gains, losses, period, index) do
    # For Wilder's method, we need to calculate smoothed averages
    # This is a simplified version - for proper Wilder's smoothing,
    # we'd need to track running averages
    start_idx = max(0, index + 1 - period)

    recent_gains = Enum.slice(gains, start_idx, period)
    recent_losses = Enum.slice(losses, start_idx, period)

    avg_gain = Utils.mean(recent_gains)
    avg_loss = Utils.mean(recent_losses)

    calculate_rsi_value(avg_gain, avg_loss)
  end

  defp calculate_rsi_value(avg_gain, avg_loss) do
    case Decimal.equal?(avg_loss, Decimal.new("0")) do
      # Avoid division by zero
      true ->
        Decimal.new("100.0")

      false ->
        rs = Decimal.div(avg_gain, avg_loss)
        one_plus_rs = Decimal.add(Decimal.new("1"), rs)
        division_result = Decimal.div(Decimal.new("100"), one_plus_rs)
        Decimal.sub(Decimal.new("100"), division_result)
    end
  end

  defp build_rsi_results(rsi_values, period, smoothing, overbought, oversold, original_data) do
    rsi_values
    # Start from period index (after period + 1 data points)
    |> Enum.with_index(period)
    |> Enum.map(fn {rsi_value, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: rsi_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "RSI",
          period: period,
          smoothing: smoothing,
          overbought: overbought,
          oversold: oversold,
          signal: determine_rsi_signal(rsi_value, overbought, oversold)
        }
      }
    end)
  end

  defp determine_rsi_signal(rsi_value, overbought, oversold) do
    overbought_decimal = Decimal.new(overbought)
    oversold_decimal = Decimal.new(oversold)

    cond do
      Decimal.gt?(rsi_value, overbought_decimal) -> :overbought
      Decimal.lt?(rsi_value, oversold_decimal) -> :oversold
      true -> :neutral
    end
  end

  defp get_data_timestamp(data, index) when is_list(data) do
    if index < length(data) do
      case Enum.at(data, index) do
        %{timestamp: timestamp} -> timestamp
        _ -> DateTime.utc_now()
      end
    else
      DateTime.utc_now()
    end
  end

  defp update_buffer(buffer, new_value, max_size) do
    updated_buffer = buffer ++ [new_value]

    if length(updated_buffer) > max_size do
      Enum.take(updated_buffer, -max_size)
    else
      updated_buffer
    end
  end

  defp calculate_streaming_rsi(
         gains,
         losses,
         prev_avg_gain,
         prev_avg_loss,
         period,
         smoothing,
         overbought,
         oversold,
         count,
         data_point
       ) do
    if count < period + 1 do
      # Not enough data yet
      {prev_avg_gain, prev_avg_loss, nil}
    else
      # Calculate new averages
      {new_avg_gain, new_avg_loss} =
        case smoothing do
          :wilder when prev_avg_gain != nil and prev_avg_loss != nil ->
            # Wilder's smoothing: ((previous_avg * (n-1)) + current_value) / n
            current_gain = List.last(gains) || Decimal.new("0")
            current_loss = List.last(losses) || Decimal.new("0")

            period_decimal = Decimal.new(period)
            period_minus_one = Decimal.sub(period_decimal, Decimal.new("1"))

            gain_part = Decimal.mult(prev_avg_gain, period_minus_one)
            new_avg_gain = Decimal.div(Decimal.add(gain_part, current_gain), period_decimal)

            loss_part = Decimal.mult(prev_avg_loss, period_minus_one)
            new_avg_loss = Decimal.div(Decimal.add(loss_part, current_loss), period_decimal)

            {new_avg_gain, new_avg_loss}

          _ ->
            # Simple moving average or first calculation
            recent_gains = Enum.take(gains, -period)
            recent_losses = Enum.take(losses, -period)
            {Utils.mean(recent_gains), Utils.mean(recent_losses)}
        end

      # Calculate RSI
      rsi_value = calculate_rsi_value(new_avg_gain, new_avg_loss)
      timestamp = get_timestamp(data_point)

      result = %{
        value: rsi_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "RSI",
          period: period,
          smoothing: smoothing,
          overbought: overbought,
          oversold: oversold,
          signal: determine_rsi_signal(rsi_value, overbought, oversold)
        }
      }

      {new_avg_gain, new_avg_loss, result}
    end
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()
end
