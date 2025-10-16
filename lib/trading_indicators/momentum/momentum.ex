defmodule TradingIndicators.Momentum.Momentum do
  @moduledoc """
  Momentum oscillator indicator implementation.

  The Momentum indicator measures the rate of change in price over a specified
  number of periods. It is one of the simplest momentum oscillators and compares
  the current price to the price n periods ago. Unlike ROC which expresses change
  as a percentage, Momentum shows the raw price difference.

  ## Formula

  **Simple Momentum:**
  Momentum = Current Price - Price n periods ago

  **Smoothed Momentum (optional):**
  Smoothed Momentum = SMA(Momentum, smoothing_period)

  Where:
  - Current Price = Current closing price (or specified source)
  - Price n periods ago = Closing price n periods in the past
  - n = lookback period (typically 10 or 14)

  ## Variants

  - **Raw Momentum**: Simple price difference (default)
  - **Smoothed Momentum**: Applies moving average smoothing
  - **Normalized Momentum**: Momentum divided by price n periods ago

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.Momentum.calculate(data, period: 3)
      iex> length(result)
      1

  ## Parameters

  - `:period` - Number of periods to look back (default: 10)
  - `:source` - Price source field to use (default: `:close`)
  - `:smoothing` - Smoothing period for momentum (default: 1, no smoothing)
  - `:normalized` - Whether to normalize by historical price (default: false)

  ## Interpretation

  - **Momentum > 0**: Upward momentum (current price higher than n periods ago)
  - **Momentum < 0**: Downward momentum (current price lower than n periods ago)
  - **Momentum crossing 0**: Potential trend change
  - **Increasing Momentum**: Accelerating trend
  - **Decreasing Momentum**: Decelerating trend

  ## Trading Applications

  1. **Trend Confirmation**: Rising momentum confirms uptrend
  2. **Divergence Analysis**: Momentum vs. price divergences
  3. **Momentum Peaks/Troughs**: Early trend change signals
  4. **Zero Line Crossovers**: Momentum crossing above/below zero

  ## Comparison with ROC

  - **Momentum**: Raw price difference (absolute terms)
  - **ROC**: Percentage change (relative terms)
  - **Use Momentum**: When comparing securities of similar price levels
  - **Use ROC**: When comparing securities of different price levels

  ## Notes

  - Requires at least `period + 1` data points for calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Can be applied to any price source (open, high, low, close)
  - More volatile than percentage-based indicators for higher-priced securities
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 10
  @default_source :close
  @default_smoothing 1
  @default_normalized false

  @doc """
  Calculates Momentum for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods to look back (default: #{@default_period})
  - `:source` - Price source (default: #{@default_source})
  - `:smoothing` - Smoothing period (default: #{@default_smoothing}, no smoothing)
  - `:normalized` - Normalize by historical price (default: #{@default_normalized})

  ## Returns

  - `{:ok, results}` - List of Momentum calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = Momentum.calculate(data, period: 10)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, @default_source),
         smoothing <- Keyword.get(opts, :smoothing, @default_smoothing),
         normalized <- Keyword.get(opts, :normalized, @default_normalized),
         :ok <- Utils.validate_data_length(data, period + 1 + smoothing - 1) do
      prices = extract_prices(data, source)
      calculate_momentum_values(prices, period, smoothing, normalized, source, data)
    end
  end

  @doc """
  Validates parameters for Momentum calculation.

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
    source = Keyword.get(opts, :source, @default_source)
    smoothing = Keyword.get(opts, :smoothing, @default_smoothing)
    normalized = Keyword.get(opts, :normalized, @default_normalized)

    with :ok <- validate_period(period, :period),
         :ok <- validate_source(source),
         :ok <- validate_period(smoothing, :smoothing),
         :ok <- validate_normalized(normalized) do
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
  Returns the minimum number of periods required for Momentum calculation.

  ## Returns

  - Default period + 1 if no options provided
  - Configured period + smoothing from options

  ## Example

      iex> TradingIndicators.Momentum.Momentum.required_periods()
      11
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

      iex> TradingIndicators.Momentum.Momentum.required_periods(period: 10, smoothing: 3)
      13
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    smoothing = Keyword.get(opts, :smoothing, @default_smoothing)
    period + smoothing
  end

  @doc """
  Returns metadata describing all parameters accepted by the Momentum indicator.

  ## Returns

  - List of parameter metadata maps
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
        description: "Number of periods to look back"
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
      }
    ]
  end

  @doc """
  Initializes streaming state for real-time Momentum calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = Momentum.init_state(period: 10)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, @default_source)
    smoothing = Keyword.get(opts, :smoothing, @default_smoothing)
    normalized = Keyword.get(opts, :normalized, @default_normalized)

    %{
      momentum_period: period,
      source: source,
      smoothing: smoothing,
      normalized: normalized,
      previous_prices: [],
      momentum_values: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, momentum_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = Momentum.init_state(period: 10)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = Momentum.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          momentum_period: period,
          source: source,
          smoothing: smoothing,
          normalized: normalized,
          previous_prices: prices,
          momentum_values: momentum_values,
          count: count
        } = _state,
        data_point
      ) do
    try do
      current_price = extract_single_price(data_point, source)
      new_count = count + 1

      # Update price buffer
      new_prices = update_buffer(prices, current_price, period + 1)

      # Calculate momentum if we have enough price data
      {new_momentum_values, result} =
        if new_count >= period + 1 do
          historical_price = List.first(new_prices)
          raw_momentum = calculate_momentum_value(current_price, historical_price, normalized)

          # Apply smoothing if specified
          updated_momentum_values = update_buffer(momentum_values, raw_momentum, smoothing)

          if smoothing > 1 and length(updated_momentum_values) >= smoothing do
            smoothed_momentum = Utils.mean(updated_momentum_values)
            timestamp = get_timestamp(data_point)

            result = %{
              value: smoothed_momentum,
              timestamp: timestamp,
              metadata: %{
                indicator: "Momentum",
                period: period,
                source: source,
                smoothing: smoothing,
                normalized: normalized,
                signal: determine_signal(smoothed_momentum)
              }
            }

            {updated_momentum_values, result}
          else
            # No smoothing or not enough data for smoothing yet
            final_momentum =
              if smoothing == 1, do: raw_momentum, else: List.last(updated_momentum_values)

            timestamp = get_timestamp(data_point)

            result =
              if smoothing == 1 or length(updated_momentum_values) >= smoothing do
                %{
                  value: final_momentum,
                  timestamp: timestamp,
                  metadata: %{
                    indicator: "Momentum",
                    period: period,
                    source: source,
                    smoothing: smoothing,
                    normalized: normalized,
                    signal: determine_signal(final_momentum)
                  }
                }
              else
                # Not enough data for smoothed result
                nil
              end

            {updated_momentum_values, result}
          end
        else
          {momentum_values, nil}
        end

      new_state = %{
        momentum_period: period,
        source: source,
        smoothing: smoothing,
        normalized: normalized,
        previous_prices: new_prices,
        momentum_values: new_momentum_values,
        count: new_count
      }

      {:ok, new_state, result}
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for Momentum streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period, _name) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period, name) do
    {:error,
     %Errors.InvalidParams{
       message: "#{name} must be a positive integer, got #{inspect(period)}",
       param: name,
       value: period,
       expected: "positive integer"
     }}
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

  defp validate_normalized(normalized) when is_boolean(normalized), do: :ok

  defp validate_normalized(normalized) do
    {:error,
     %Errors.InvalidParams{
       message: "Normalized must be a boolean, got #{inspect(normalized)}",
       param: :normalized,
       value: normalized,
       expected: "boolean"
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

  defp extract_single_price(price, _source) when Decimal.is_decimal(price) do
    price
  end

  defp extract_single_price(price, _source) when is_number(price) do
    Decimal.new(price)
  end

  defp extract_single_price(%{} = data_point, source) do
    Map.fetch!(data_point, source)
  end

  defp calculate_momentum_values(prices, period, smoothing, normalized, source, original_data) do
    # Create pairs of current price and price n periods ago
    current_prices = Enum.drop(prices, period)
    historical_prices = Enum.take(prices, length(prices) - period)

    # Calculate raw momentum values
    raw_momentum_values =
      Enum.zip(current_prices, historical_prices)
      |> Enum.map(fn {current, historical} ->
        calculate_momentum_value(current, historical, normalized)
      end)

    # Apply smoothing if specified
    final_momentum_values =
      if smoothing > 1 do
        apply_smoothing(raw_momentum_values, smoothing)
      else
        raw_momentum_values
      end

    # Build results
    results =
      build_momentum_results(
        final_momentum_values,
        period,
        smoothing,
        normalized,
        source,
        original_data
      )

    {:ok, results}
  end

  defp calculate_momentum_value(current_price, historical_price, normalized) do
    difference = Decimal.sub(current_price, historical_price)

    case normalized do
      true ->
        # Normalize by historical price (similar to percentage change but without * 100)
        case Decimal.equal?(historical_price, Decimal.new("0")) do
          true -> Decimal.new("0")
          false -> Decimal.div(difference, historical_price)
        end

      false ->
        # Raw price difference
        difference
    end
  end

  defp apply_smoothing(values, smoothing_period) do
    Utils.sliding_window(values, smoothing_period)
    |> Enum.map(&Utils.mean/1)
  end

  defp build_momentum_results(momentum_values, period, smoothing, normalized, source, original_data) do
    # Adjust starting index based on smoothing
    start_index = period + smoothing - 1

    momentum_values
    |> Enum.with_index(start_index)
    |> Enum.map(fn {momentum_value, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: momentum_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "Momentum",
          period: period,
          source: source,
          smoothing: smoothing,
          normalized: normalized,
          signal: determine_signal(momentum_value)
        }
      }
    end)
  end

  defp determine_signal(momentum_value) do
    zero = Decimal.new("0")

    cond do
      Decimal.gt?(momentum_value, zero) -> :bullish
      Decimal.lt?(momentum_value, zero) -> :bearish
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

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp update_buffer(buffer, new_value, max_size) do
    updated_buffer = buffer ++ [new_value]

    if length(updated_buffer) > max_size do
      Enum.take(updated_buffer, -max_size)
    else
      updated_buffer
    end
  end
end
