defmodule TradingIndicators.Momentum.ROC do
  @moduledoc """
  Rate of Change (ROC) momentum oscillator implementation.

  The Rate of Change is a momentum oscillator that measures the percentage change
  in price between the current price and the price n periods ago. It oscillates
  around zero, with positive values indicating upward momentum and negative values
  indicating downward momentum.

  ## Formula

  **Percentage Rate of Change:**
  ROC% = ((Current Price - Price n periods ago) / Price n periods ago) * 100

  **Price Rate of Change:**
  ROC = Current Price - Price n periods ago

  Where:
  - Current Price = Current closing price (or specified source)
  - Price n periods ago = Closing price n periods in the past
  - n = lookback period (typically 12 or 25)

  ## Variants

  - **Percentage ROC**: Expresses change as a percentage (default)
  - **Price ROC**: Expresses change in absolute price terms
  - **Momentum**: Simple price difference (ROC = Current - Previous)

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.ROC.calculate(data, period: 3)
      iex> length(result)
      1

  ## Parameters

  - `:period` - Number of periods to look back (default: 12)
  - `:source` - Price source field to use (default: `:close`)
  - `:variant` - ROC variant (`:percentage` or `:price`, default: `:percentage`)

  ## Interpretation

  - **ROC > 0**: Upward momentum (current price higher than n periods ago)
  - **ROC < 0**: Downward momentum (current price lower than n periods ago)
  - **ROC crossing 0**: Potential trend change
  - **Extreme values**: May indicate overbought/oversold conditions
  - **Divergences**: When ROC and price move in opposite directions

  ## Trading Applications

  1. **Trend Identification**: ROC direction indicates momentum direction
  2. **Zero Line Crossovers**: ROC crossing above/below zero
  3. **Divergence Analysis**: ROC vs. price divergences
  4. **Momentum Comparison**: Compare momentum across different timeframes

  ## Notes

  - Requires at least `period + 1` data points for calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Can be applied to any price source (open, high, low, close)
  - Sensitive to the chosen period length
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 12
  @default_source :close
  @default_variant :percentage

  @doc """
  Calculates Rate of Change for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods to look back (default: #{@default_period})
  - `:source` - Price source (default: #{@default_source})
  - `:variant` - ROC variant (`:percentage` or `:price`, default: #{@default_variant})

  ## Returns

  - `{:ok, results}` - List of ROC calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = ROC.calculate(data, period: 12)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, @default_source),
         variant <- Keyword.get(opts, :variant, @default_variant),
         :ok <- Utils.validate_data_length(data, period + 1) do
      prices = extract_prices(data, source)
      calculate_roc_values(prices, period, variant, source, data)
    end
  end

  @doc """
  Validates parameters for ROC calculation.

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
    variant = Keyword.get(opts, :variant, @default_variant)

    with :ok <- validate_period(period),
         :ok <- validate_source(source),
         :ok <- validate_variant(variant) do
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
  Returns the minimum number of periods required for ROC calculation.

  ## Returns

  - Default period + 1 if no options provided
  - Configured period + 1 from options

  ## Example

      iex> TradingIndicators.Momentum.ROC.required_periods()
      13
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

      iex> TradingIndicators.Momentum.ROC.required_periods(period: 10)
      11
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    period + 1
  end

  @doc """
  Returns metadata describing all parameters accepted by the ROC indicator.

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
  Returns metadata describing the output fields for ROC.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Momentum.ROC.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description:
        "Rate of Change - momentum indicator measuring percentage price change over time",
      example: "roc_12 > 0",
      unit: "%"
    }
  end

  @doc """
  Initializes streaming state for real-time ROC calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = ROC.init_state(period: 12)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, @default_source)
    variant = Keyword.get(opts, :variant, @default_variant)

    %{
      roc_period: period,
      source: source,
      variant: variant,
      historical_prices: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, roc_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = ROC.init_state(period: 12)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = ROC.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          roc_period: period,
          source: source,
          variant: variant,
          historical_prices: prices,
          count: count
        } = _state,
        data_point
      ) do
    try do
      current_price = extract_single_price(data_point, source)
      new_count = count + 1

      # Update price buffer
      new_prices = update_buffer(prices, current_price, period + 1)

      new_state = %{
        roc_period: period,
        source: source,
        variant: variant,
        historical_prices: new_prices,
        count: new_count
      }

      # Calculate ROC if we have enough data
      if new_count >= period + 1 do
        historical_price = List.first(new_prices)
        roc_value = calculate_roc_value(current_price, historical_price, variant)
        timestamp = get_timestamp(data_point)

        result = %{
          value: roc_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "ROC",
            period: period,
            source: source,
            variant: variant,
            signal: determine_signal(roc_value)
          }
        }

        {:ok, new_state, result}
      else
        {:ok, new_state, nil}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for ROC streaming",
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

  defp validate_variant(variant) when variant in [:percentage, :price], do: :ok

  defp validate_variant(variant) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid variant: #{inspect(variant)}",
       param: :variant,
       value: variant,
       expected: "one of [:percentage, :price]"
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

  defp calculate_roc_values(prices, period, variant, source, original_data) do
    # Create pairs of current price and price n periods ago
    current_prices = Enum.drop(prices, period)
    historical_prices = Enum.take(prices, length(prices) - period)

    roc_values =
      Enum.zip(current_prices, historical_prices)
      |> Enum.map(fn {current, historical} ->
        calculate_roc_value(current, historical, variant)
      end)

    # Build results
    results = build_roc_results(roc_values, period, variant, source, original_data)

    {:ok, results}
  end

  defp calculate_roc_value(current_price, historical_price, variant) do
    case variant do
      :percentage ->
        calculate_percentage_roc(current_price, historical_price)

      :price ->
        calculate_price_roc(current_price, historical_price)
    end
  end

  defp calculate_percentage_roc(current_price, historical_price) do
    case Decimal.equal?(historical_price, Decimal.new("0")) do
      # Avoid division by zero
      true ->
        Decimal.new("0")

      false ->
        difference = Decimal.sub(current_price, historical_price)
        ratio = Decimal.div(difference, historical_price)
        Decimal.mult(ratio, Decimal.new("100"))
    end
  end

  defp calculate_price_roc(current_price, historical_price) do
    Decimal.sub(current_price, historical_price)
  end

  defp build_roc_results(roc_values, period, variant, source, original_data) do
    roc_values
    |> Enum.with_index(period)
    |> Enum.map(fn {roc_value, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: roc_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "ROC",
          period: period,
          source: source,
          variant: variant,
          signal: determine_signal(roc_value)
        }
      }
    end)
  end

  defp determine_signal(roc_value) do
    zero = Decimal.new("0")

    cond do
      Decimal.gt?(roc_value, zero) -> :bullish
      Decimal.lt?(roc_value, zero) -> :bearish
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
