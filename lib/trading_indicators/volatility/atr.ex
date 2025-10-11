defmodule TradingIndicators.Volatility.ATR do
  @moduledoc """
  Average True Range (ATR) volatility indicator implementation.

  The Average True Range (ATR) is a technical analysis indicator that measures 
  volatility by decomposing the entire range of an asset price for that period.
  It was introduced by J. Welles Wilder in his book "New Concepts in Technical 
  Trading Systems."

  ## Formula

  True Range = max(High - Low, abs(High - Previous Close), abs(Low - Previous Close))
  ATR = Smoothed average of True Range values over specified period

  ## Smoothing Methods

  - `:sma` - Simple Moving Average (arithmetic mean)
  - `:ema` - Exponential Moving Average (exponentially weighted)
  - `:rma` - Running Moving Average (Wilder's original method)

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{high: Decimal.new("108"), low: Decimal.new("104"), close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volatility.ATR.calculate(data, period: 2)
      iex> [_first, second | _] = result
      iex> Decimal.round(second.value, 2)
      Decimal.new("4.75")

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, must be >= 1)
  - `:smoothing` - Smoothing method (`:sma`, `:ema`, `:rma`) (default: `:rma`)

  ## Notes

  - Requires at least `period` number of data points
  - Always uses High, Low, and Close prices (no source selection)
  - Returns results only when sufficient data is available
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Original Wilder's method uses RMA (similar to EMA with alpha=1/period)
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 14
  @default_smoothing :rma

  @doc """
  Calculates Average True Range for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:smoothing` - Smoothing method (default: #{@default_smoothing})

  ## Returns

  - `{:ok, results}` - List of ATR calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = ATR.calculate(data, period: 14, smoothing: :rma)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         smoothing <- Keyword.get(opts, :smoothing, @default_smoothing),
         :ok <- Utils.validate_data_length(data, period),
         :ok <- validate_ohlc_data(data) do
      true_ranges = calculate_true_ranges(data)
      calculate_atr_values(true_ranges, period, smoothing, data)
    end
  end

  @doc """
  Validates parameters for ATR calculation.

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
    smoothing = Keyword.get(opts, :smoothing, @default_smoothing)

    with :ok <- validate_period(period),
         :ok <- validate_smoothing(smoothing) do
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
  Returns the minimum number of periods required for ATR calculation.

  ## Returns

  - Default period if no options provided

  ## Example

      iex> TradingIndicators.Volatility.ATR.required_periods()
      14
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

      iex> TradingIndicators.Volatility.ATR.required_periods(period: 21)
      21
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Initializes streaming state for real-time ATR calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = ATR.init_state(period: 14, smoothing: :rma)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    smoothing = Keyword.get(opts, :smoothing, @default_smoothing)

    %{
      period: period,
      smoothing: smoothing,
      true_ranges: [],
      atr_value: nil,
      previous_close: nil,
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, atr_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = ATR.init_state(period: 3)
      data_point = %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = ATR.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          smoothing: smoothing,
          true_ranges: true_ranges,
          atr_value: atr_value,
          previous_close: previous_close,
          count: count
        } = _state,
        %{high: _high, low: _low, close: _close} = data_point
      ) do
    try do
      # Calculate True Range for current data point
      true_range = calculate_single_true_range(data_point, previous_close)
      new_true_ranges = update_buffer(true_ranges, true_range, period)
      new_count = count + 1

      # Calculate new ATR value based on smoothing method
      new_atr_value =
        if new_count >= period do
          case smoothing do
            :sma -> Utils.mean(new_true_ranges)
            :ema -> calculate_ema_atr(atr_value, true_range, period)
            :rma -> calculate_rma_atr(atr_value, true_range, period, new_count)
          end
        else
          atr_value
        end

      new_state = %{
        period: period,
        smoothing: smoothing,
        true_ranges: new_true_ranges,
        atr_value: new_atr_value,
        previous_close: data_point.close,
        count: new_count
      }

      if new_count >= period and new_atr_value do
        result = %{
          value: new_atr_value,
          timestamp: get_timestamp(data_point),
          metadata: %{
            indicator: "ATR",
            period: period,
            smoothing: smoothing,
            true_range: true_range
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
       message: "Invalid state format for ATR streaming or data point missing OHLC fields",
       operation: :update_state,
       reason: "malformed state or invalid data point"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
  end

  defp validate_smoothing(smoothing) when smoothing in [:sma, :ema, :rma], do: :ok

  defp validate_smoothing(smoothing) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid smoothing method: #{inspect(smoothing)}",
       param: :smoothing,
       value: smoothing,
       expected: "one of [:sma, :ema, :rma]"
     }}
  end

  defp validate_ohlc_data([]), do: :ok
  defp validate_ohlc_data([%{high: _, low: _, close: _} | rest]), do: validate_ohlc_data(rest)

  defp validate_ohlc_data([invalid | _rest]) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "ATR requires OHLC data with high, low, and close fields",
       expected: "map with :high, :low, :close keys",
       received: inspect(invalid)
     }}
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_true_ranges([]), do: []

  defp calculate_true_ranges([first | rest]) do
    first_tr = Utils.true_range(first, nil)

    rest_trs =
      [first | rest]
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, curr] -> Utils.true_range(curr, prev) end)

    [first_tr | rest_trs]
  end

  defp calculate_single_true_range(current, nil) do
    Utils.true_range(current, nil)
  end

  defp calculate_single_true_range(current, previous_close) do
    previous = %{close: previous_close}
    Utils.true_range(current, previous)
  end

  defp calculate_atr_values(true_ranges, period, smoothing, original_data) do
    case smoothing do
      :sma -> calculate_sma_atr(true_ranges, period, original_data)
      :ema -> calculate_ema_atr_series(true_ranges, period, original_data)
      :rma -> calculate_rma_atr_series(true_ranges, period, original_data)
    end
  end

  defp calculate_sma_atr(true_ranges, period, original_data) do
    results =
      true_ranges
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {window, index} ->
        atr_value = Utils.mean(window)
        timestamp = get_data_timestamp(original_data, index)

        %{
          value: atr_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "ATR",
            period: period,
            smoothing: :sma,
            true_range: List.last(window)
          }
        }
      end)

    {:ok, results}
  end

  defp calculate_ema_atr_series(true_ranges, period, original_data) do
    alpha = Decimal.div(Decimal.new("2"), Decimal.new(period + 1))

    {results, _final_ema} =
      true_ranges
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {tr, index}, {acc, prev_ema} ->
        current_ema =
          if prev_ema do
            # EMA = α * current_value + (1 - α) * previous_ema
            one_minus_alpha = Decimal.sub(Decimal.new("1"), alpha)
            weighted_current = Decimal.mult(alpha, tr)
            weighted_prev = Decimal.mult(one_minus_alpha, prev_ema)
            Decimal.add(weighted_current, weighted_prev)
          else
            # First value is the TR itself
            tr
          end

        if index >= period - 1 do
          result = %{
            value: current_ema,
            timestamp: get_data_timestamp(original_data, index),
            metadata: %{
              indicator: "ATR",
              period: period,
              smoothing: :ema,
              true_range: tr
            }
          }

          {[result | acc], current_ema}
        else
          {acc, current_ema}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  defp calculate_rma_atr_series(true_ranges, period, original_data) do
    {results, _final_rma} =
      true_ranges
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {tr, index}, {acc, prev_rma} ->
        current_rma =
          if prev_rma do
            # RMA = ((period - 1) * prev_rma + current_value) / period
            period_decimal = Decimal.new(period)
            period_minus_one = Decimal.new(period - 1)
            weighted_prev = Decimal.mult(period_minus_one, prev_rma)
            sum = Decimal.add(weighted_prev, tr)
            Decimal.div(sum, period_decimal)
          else
            # First value is the TR itself
            tr
          end

        if index >= period - 1 do
          result = %{
            value: current_rma,
            timestamp: get_data_timestamp(original_data, index),
            metadata: %{
              indicator: "ATR",
              period: period,
              smoothing: :rma,
              true_range: tr
            }
          }

          {[result | acc], current_rma}
        else
          {acc, current_rma}
        end
      end)

    {:ok, Enum.reverse(results)}
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

  defp update_buffer(buffer, new_value, max_size) do
    updated_buffer = buffer ++ [new_value]

    if length(updated_buffer) > max_size do
      # Take last N elements
      Enum.take(updated_buffer, -max_size)
    else
      updated_buffer
    end
  end

  defp calculate_ema_atr(nil, true_range, _period), do: true_range

  defp calculate_ema_atr(previous_atr, true_range, period) do
    alpha = Decimal.div(Decimal.new("2"), Decimal.new(period + 1))
    one_minus_alpha = Decimal.sub(Decimal.new("1"), alpha)
    weighted_current = Decimal.mult(alpha, true_range)
    weighted_prev = Decimal.mult(one_minus_alpha, previous_atr)
    Decimal.add(weighted_current, weighted_prev)
  end

  defp calculate_rma_atr(nil, true_range, _period, _count), do: true_range

  defp calculate_rma_atr(previous_atr, true_range, period, count) when count >= period do
    period_decimal = Decimal.new(period)
    period_minus_one = Decimal.new(period - 1)
    weighted_prev = Decimal.mult(period_minus_one, previous_atr)
    sum = Decimal.add(weighted_prev, true_range)
    Decimal.div(sum, period_decimal)
  end

  defp calculate_rma_atr(_previous_atr, true_range, _period, _count), do: true_range
end
