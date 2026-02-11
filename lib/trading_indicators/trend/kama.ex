defmodule TradingIndicators.Trend.KAMA do
  @moduledoc """
  Kaufman's Adaptive Moving Average (KAMA) indicator implementation.

  KAMA is a moving average designed to account for market noise and volatility.
  It adapts its smoothing factor based on the efficiency ratio, becoming more
  responsive in trending markets and less sensitive in sideways markets.

  ## Formula

  1. Change = |Close - Close[n periods ago]|
  2. Volatility = Sum of |Close - Close[1 period ago]| over n periods  
  3. Efficiency Ratio (ER) = Change / Volatility
  4. Smoothing Constant (SC) = (ER × (fastest SC - slowest SC) + slowest SC)²
  5. KAMA = KAMA[previous] + SC × (Close - KAMA[previous])

  Where:
  - Fastest SC = 2/(fast_period + 1) (typically fast_period = 2)
  - Slowest SC = 2/(slow_period + 1) (typically slow_period = 30)

  ## Examples

      iex> data = for i <- 0..15 do
      ...>   price = 100 + i * 0.5  
      ...>   %{close: Decimal.new(to_string(price)), timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)}
      ...> end
      iex> {:ok, result} = TradingIndicators.Trend.KAMA.calculate(data, period: 10)
      iex> length(result) >= 1
      true

  ## Parameters

  - `:period` - Number of periods for efficiency ratio calculation (default: 10)
  - `:fast_period` - Fast smoothing period (default: 2)
  - `:slow_period` - Slow smoothing period (default: 30)
  - `:source` - Source field to use: `:open`, `:high`, `:low`, `:close`, or `:volume` (default: `:close`)

  ## Notes

  - Adapts to market conditions automatically
  - More responsive during trending periods
  - Less sensitive during consolidation periods  
  - Requires at least `period + 1` data points
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 10
  @default_fast_period 2
  @default_slow_period 30

  @impl true
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         fast_period <- Keyword.get(opts, :fast_period, @default_fast_period),
         slow_period <- Keyword.get(opts, :slow_period, @default_slow_period),
         source <- Keyword.get(opts, :source, :close),
         :ok <- Utils.validate_data_length(data, period + 1) do
      prices = extract_prices(data, source)
      calculate_kama_values(prices, period, fast_period, slow_period, data)
    end
  end

  @impl true
  def validate_params(opts) when is_list(opts) do
    period = Keyword.get(opts, :period, @default_period)
    fast_period = Keyword.get(opts, :fast_period, @default_fast_period)
    slow_period = Keyword.get(opts, :slow_period, @default_slow_period)
    source = Keyword.get(opts, :source, :close)

    with :ok <- validate_period(period, :period),
         :ok <- validate_period(fast_period, :fast_period),
         :ok <- validate_period(slow_period, :slow_period),
         :ok <- validate_period_relationship(fast_period, slow_period),
         :ok <- validate_source(source) do
      :ok
    end
  end

  def validate_params(_opts),
    do: {:error, %Errors.InvalidParams{message: "Options must be a keyword list"}}

  @impl true
  def required_periods, do: @default_period + 1

  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period) + 1
  end

  @doc """
  Returns metadata describing all parameters accepted by the KAMA indicator.

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
        description: "Number of periods for efficiency ratio calculation"
      },
      %Types.ParamMetadata{
        name: :fast_period,
        type: :integer,
        default: @default_fast_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Fast smoothing period"
      },
      %Types.ParamMetadata{
        name: :slow_period,
        type: :integer,
        default: @default_slow_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Slow smoothing period"
      },
      %Types.ParamMetadata{
        name: :source,
        type: :atom,
        default: :close,
        required: false,
        min: nil,
        max: nil,
        options: [:open, :high, :low, :close, :volume],
        description: "Source price field to use"
      }
    ]
  end

  @doc """
  Returns metadata describing the output fields for KAMA.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Trend.KAMA.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description:
        "Kaufman's Adaptive Moving Average - self-adjusting moving average based on market volatility",
      example: "kama_10 > close",
      unit: "price"
    }
  end

  @impl true
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    fast_period = Keyword.get(opts, :fast_period, @default_fast_period)
    slow_period = Keyword.get(opts, :slow_period, @default_slow_period)
    source = Keyword.get(opts, :source, :close)

    %{
      period: period,
      fast_period: fast_period,
      slow_period: slow_period,
      source: source,
      prices: [],
      kama_value: nil,
      count: 0,
      fast_sc: calculate_smoothing_constant(fast_period),
      slow_sc: calculate_smoothing_constant(slow_period)
    }
  end

  @impl true
  def update_state(
        %{
          period: period,
          fast_period: fast_period,
          slow_period: slow_period,
          source: source,
          prices: prices,
          kama_value: kama_value,
          count: count,
          fast_sc: fast_sc,
          slow_sc: slow_sc
        } = _state,
        data_point
      ) do
    try do
      price = extract_single_price(data_point, source)
      new_prices = update_price_buffer(prices, price, period + 1)
      new_count = count + 1

      new_state_base = %{
        period: period,
        fast_period: fast_period,
        slow_period: slow_period,
        source: source,
        prices: new_prices,
        count: new_count,
        fast_sc: fast_sc,
        slow_sc: slow_sc
      }

      if new_count > period do
        # Calculate KAMA
        er = calculate_efficiency_ratio(new_prices, period)
        sc = calculate_adaptive_smoothing_constant(er, fast_sc, slow_sc)

        new_kama =
          if kama_value do
            # KAMA = KAMA_prev + SC × (Price - KAMA_prev)
            diff = Decimal.sub(price, kama_value)
            adjustment = Decimal.mult(sc, diff)
            Decimal.add(kama_value, adjustment)
          else
            # First KAMA value = current price
            price
          end

        timestamp = get_timestamp(data_point)

        result = %{
          value: new_kama,
          timestamp: timestamp,
          metadata: %{
            indicator: "KAMA",
            period: period,
            fast_period: fast_period,
            slow_period: slow_period,
            source: source,
            efficiency_ratio: Decimal.round(er, 4)
          }
        }

        new_state = Map.put(new_state_base, :kama_value, new_kama)
        {:ok, new_state, result}
      else
        new_state = Map.put(new_state_base, :kama_value, kama_value)
        {:ok, new_state, nil}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error, %Errors.StreamStateError{message: "Invalid KAMA state format"}}
  end

  # Private functions

  defp validate_period(period, _name) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period, name) do
    {:error, %Errors.InvalidParams{param: name, value: period, expected: "positive integer"}}
  end

  defp validate_period_relationship(fast, slow) when fast < slow, do: :ok

  defp validate_period_relationship(fast, slow) do
    {:error,
     %Errors.InvalidParams{message: "Fast period (#{fast}) must be less than slow period (#{slow})"}}
  end

  defp validate_source(source) when source in [:open, :high, :low, :close, :volume], do: :ok

  defp validate_source(source) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid source: #{inspect(source)}",
       param: :source,
       value: source,
       expected: "one of [:open, :high, :low, :close, :volume]"
     }}
  end

  defp extract_prices(data, source) when is_list(data) do
    case List.first(data) do
      %Decimal{} -> data
      %{} -> extract_ohlcv_prices(data, source)
      _ -> data
    end
  end

  defp extract_ohlcv_prices(data, :close), do: Utils.extract_closes(data)
  defp extract_ohlcv_prices(data, :open), do: Utils.extract_opens(data)
  defp extract_ohlcv_prices(data, :high), do: Utils.extract_highs(data)
  defp extract_ohlcv_prices(data, :low), do: Utils.extract_lows(data)

  defp extract_ohlcv_prices(data, :volume), do: Utils.extract_volumes_as_decimal(data)

  defp extract_single_price(%{} = data_point, :volume),
    do: Utils.extract_volume_as_decimal(data_point)

  defp extract_single_price(%{} = data_point, source), do: Map.fetch!(data_point, source)
  defp extract_single_price(price, _source) when Decimal.is_decimal(price), do: price
  defp extract_single_price(price, _source) when is_number(price), do: Decimal.new(price)

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_kama_values(prices, period, fast_period, slow_period, original_data) do
    fast_sc = calculate_smoothing_constant(fast_period)
    slow_sc = calculate_smoothing_constant(slow_period)

    results =
      prices
      |> Enum.chunk_every(period + 1, 1, :discard)
      |> Enum.with_index(period)
      |> Enum.reduce({[], nil}, fn {price_window, index}, {acc, prev_kama} ->
        current_price = List.last(price_window)

        er = calculate_efficiency_ratio(price_window, period)
        sc = calculate_adaptive_smoothing_constant(er, fast_sc, slow_sc)

        kama =
          if prev_kama do
            diff = Decimal.sub(current_price, prev_kama)
            adjustment = Decimal.mult(sc, diff)
            Decimal.add(prev_kama, adjustment)
          else
            current_price
          end

        timestamp = get_data_timestamp(original_data, index)

        result = %{
          value: kama,
          timestamp: timestamp,
          metadata: %{
            indicator: "KAMA",
            period: period,
            fast_period: fast_period,
            slow_period: slow_period,
            source: :close,
            efficiency_ratio: Decimal.round(er, 4)
          }
        }

        {[result | acc], kama}
      end)
      |> elem(0)
      |> Enum.reverse()

    {:ok, results}
  end

  defp calculate_efficiency_ratio(price_window, _period) do
    current_price = List.last(price_window)
    first_price = List.first(price_window)

    # Change = |current - first|
    change = Decimal.abs(Decimal.sub(current_price, first_price))

    # Volatility = sum of |price[i] - price[i-1]| over period
    volatility =
      price_window
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(Decimal.new("0"), fn [prev, curr], acc ->
        diff = Decimal.abs(Decimal.sub(curr, prev))
        Decimal.add(acc, diff)
      end)

    # ER = Change / Volatility (handle division by zero)
    if Decimal.equal?(volatility, Decimal.new("0")) do
      # Maximum efficiency when no volatility
      Decimal.new("1")
    else
      Decimal.div(change, volatility)
    end
  end

  defp calculate_smoothing_constant(period) do
    # SC = 2 / (period + 1)
    Decimal.div(Decimal.new("2"), Decimal.new(period + 1))
  end

  defp calculate_adaptive_smoothing_constant(er, fast_sc, slow_sc) do
    # SC = (ER × (fast_SC - slow_SC) + slow_SC)²
    sc_diff = Decimal.sub(fast_sc, slow_sc)
    scaled_er = Decimal.mult(er, sc_diff)
    linear_sc = Decimal.add(scaled_er, slow_sc)
    # Square it
    Decimal.mult(linear_sc, linear_sc)
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

  defp update_price_buffer(prices, new_price, max_size) do
    updated_prices = prices ++ [new_price]

    if length(updated_prices) > max_size do
      Enum.take(updated_prices, -max_size)
    else
      updated_prices
    end
  end
end
