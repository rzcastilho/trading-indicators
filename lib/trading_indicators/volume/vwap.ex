defmodule TradingIndicators.Volume.VWAP do
  @moduledoc """
  Volume Weighted Average Price (VWAP) indicator implementation.

  VWAP is a trading benchmark that calculates the average price weighted by volume.
  It provides the true average price of a security by taking into account both price
  and volume. VWAP is commonly used by institutional traders to assess whether they
  bought or sold at a good price relative to the rest of the market.

  ## Formula

  VWAP = Σ(Price × Volume) / Σ(Volume)

  Where Price can be:
  - Close price (default)
  - Typical Price: (High + Low + Close) / 3
  - Weighted Price: (High + Low + 2*Close) / 4

  ## Variants

  - `:close` - Uses closing price (simple VWAP)
  - `:typical` - Uses typical price ((High + Low + Close) / 3)
  - `:weighted` - Uses weighted price ((High + Low + 2*Close) / 4)

  ## Session Reset Options

  - `:none` - Cumulative VWAP from start (default)
  - `:daily` - Reset at start of each trading day
  - `:weekly` - Reset at start of each trading week
  - `:monthly` - Reset at start of each trading month

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volume.VWAP.calculate(data, variant: :typical)
      iex> [first | _] = result
      iex> Decimal.round(first.value, 2)
      Decimal.new("102.33")

  ## Parameters

  - `:variant` - Price calculation variant (`:close`, `:typical`, `:weighted`) (default: `:close`)
  - `:session_reset` - Reset frequency (`:none`, `:daily`, `:weekly`, `:monthly`) (default: `:none`)

  ## Usage Notes

  - Returns results for all data points
  - Requires OHLCV data with volume
  - Uses precise Decimal arithmetic
  - Supports session-based resets based on timestamps
  - Volume must be positive (zero volume periods are skipped)
  - Useful for determining fair value and trading benchmarks

  ## Interpretation

  - **Price above VWAP** - Security trading at premium (bullish sentiment)
  - **Price below VWAP** - Security trading at discount (bearish sentiment)
  - **VWAP slope** - Direction indicates overall price trend
  - **Distance from VWAP** - Measures how far current price deviates from average
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_variant :close
  @default_session_reset :none

  @doc """
  Calculates Volume Weighted Average Price for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:variant` - Price variant (default: #{@default_variant})
  - `:session_reset` - Session reset frequency (default: #{@default_session_reset})

  ## Returns

  - `{:ok, results}` - List of VWAP calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      ]
      {:ok, result} = VWAP.calculate(data, variant: :typical, session_reset: :daily)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         variant <- Keyword.get(opts, :variant, @default_variant),
         session_reset <- Keyword.get(opts, :session_reset, @default_session_reset),
         :ok <- Utils.validate_data_length(data, 1),
         :ok <- validate_ohlcv_data(data, variant) do
      calculate_vwap_values(data, variant, session_reset)
    end
  end

  @doc """
  Validates parameters for VWAP calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    variant = Keyword.get(opts, :variant, @default_variant)
    session_reset = Keyword.get(opts, :session_reset, @default_session_reset)

    with :ok <- validate_variant(variant),
         :ok <- validate_session_reset(session_reset) do
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
  Returns the minimum number of periods required for VWAP calculation.

  ## Returns

  - Always 1 (VWAP can be calculated from the first data point)

  ## Example

      iex> TradingIndicators.Volume.VWAP.required_periods()
      1
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: 1

  @doc """
  Returns metadata describing all parameters accepted by the VWAP indicator.

  ## Returns

  - List of parameter metadata maps
  """
  @impl true
  @spec parameter_metadata() :: [Types.param_metadata()]
  def parameter_metadata do
    []
  end

  @doc """
  Initializes streaming state for real-time VWAP calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = VWAP.init_state(variant: :typical, session_reset: :daily)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    variant = Keyword.get(opts, :variant, @default_variant)
    session_reset = Keyword.get(opts, :session_reset, @default_session_reset)

    %{
      variant: variant,
      session_reset: session_reset,
      cumulative_price_volume: Decimal.new("0"),
      cumulative_volume: Decimal.new("0"),
      current_session_start: nil,
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, vwap_result}` - Updated state with result
  - `{:error, reason}` - Error occurred

  ## Example

      state = VWAP.init_state(variant: :close)
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = VWAP.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          variant: variant,
          session_reset: session_reset,
          cumulative_price_volume: cum_pv,
          cumulative_volume: cum_vol,
          current_session_start: session_start,
          count: count
        } = _state,
        data_point
      ) do
    try do
      # Validate the data point
      with :ok <- validate_single_ohlcv_data(data_point, variant) do
        timestamp = get_timestamp(data_point)

        # Check if we need to reset for new session
        should_reset = should_reset_session?(session_reset, session_start, timestamp)

        {new_cum_pv, new_cum_vol, new_session_start} =
          if should_reset do
            {Decimal.new("0"), Decimal.new("0"), get_session_start(session_reset, timestamp)}
          else
            {cum_pv, cum_vol, session_start || get_session_start(session_reset, timestamp)}
          end

        # Skip zero volume periods
        if data_point.volume == 0 do
          new_state = %{
            variant: variant,
            session_reset: session_reset,
            cumulative_price_volume: new_cum_pv,
            cumulative_volume: new_cum_vol,
            current_session_start: new_session_start,
            count: count + 1
          }

          {:ok, new_state, nil}
        else
          # Calculate price based on variant
          price = calculate_price_by_variant(data_point, variant)
          volume_decimal = Decimal.new(data_point.volume)

          # Update cumulative values
          price_volume = Decimal.mult(price, volume_decimal)
          final_cum_pv = Decimal.add(new_cum_pv, price_volume)
          final_cum_vol = Decimal.add(new_cum_vol, volume_decimal)

          # Calculate VWAP
          vwap =
            if Decimal.positive?(final_cum_vol) do
              Decimal.div(final_cum_pv, final_cum_vol)
            else
              Decimal.new("0")
            end

          new_state = %{
            variant: variant,
            session_reset: session_reset,
            cumulative_price_volume: final_cum_pv,
            cumulative_volume: final_cum_vol,
            current_session_start: new_session_start,
            count: count + 1
          }

          result = %{
            value: vwap,
            timestamp: timestamp,
            metadata: %{
              indicator: "VWAP",
              variant: variant,
              session_reset: session_reset,
              price_used: price,
              volume: data_point.volume,
              cumulative_volume: final_cum_vol,
              session_reset_occurred: should_reset
            }
          }

          {:ok, new_state, result}
        end
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for VWAP streaming or data point missing required fields",
       operation: :update_state,
       reason: "malformed state or invalid data point"
     }}
  end

  # Private functions

  defp validate_variant(variant) when variant in [:close, :typical, :weighted], do: :ok

  defp validate_variant(variant) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid VWAP variant: #{inspect(variant)}",
       param: :variant,
       value: variant,
       expected: "one of [:close, :typical, :weighted]"
     }}
  end

  defp validate_session_reset(session_reset)
       when session_reset in [:none, :daily, :weekly, :monthly],
       do: :ok

  defp validate_session_reset(session_reset) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid session reset: #{inspect(session_reset)}",
       param: :session_reset,
       value: session_reset,
       expected: "one of [:none, :daily, :weekly, :monthly]"
     }}
  end

  defp validate_ohlcv_data([], _variant), do: :ok

  defp validate_ohlcv_data(data, variant) do
    Enum.reduce_while(data, :ok, fn data_point, _acc ->
      case validate_single_ohlcv_data(data_point, variant) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_single_ohlcv_data(%{volume: volume} = data_point, variant) do
    # Check volume
    with :ok <- validate_volume(volume, data_point) do
      # Check required price fields based on variant
      case variant do
        :close ->
          validate_close_field(data_point)

        :typical ->
          validate_hlc_fields(data_point)

        :weighted ->
          validate_hlc_fields(data_point)
      end
    end
  end

  defp validate_single_ohlcv_data(invalid, _variant) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "VWAP requires data with volume field",
       expected: "map with :volume key",
       received: inspect(invalid)
     }}
  end

  defp validate_volume(volume, _data_point) when is_integer(volume) and volume >= 0, do: :ok

  defp validate_volume(volume, data_point) do
    {:error,
     %Errors.ValidationError{
       message: "Volume must be a non-negative integer",
       field: :volume,
       value: volume,
       constraint: "must be non-negative integer, got #{inspect(volume)} in #{inspect(data_point)}"
     }}
  end

  defp validate_close_field(%{close: close}) when is_struct(close, Decimal) do
    if Decimal.negative?(close) do
      {:error, Errors.negative_price(:close, close)}
    else
      :ok
    end
  end

  defp validate_close_field(data_point) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "VWAP requires close field as Decimal",
       expected: "map with :close key as Decimal",
       received: inspect(data_point)
     }}
  end

  defp validate_hlc_fields(%{high: high, low: low, close: close})
       when is_struct(high, Decimal) and is_struct(low, Decimal) and is_struct(close, Decimal) do
    cond do
      Decimal.negative?(high) ->
        {:error, Errors.negative_price(:high, high)}

      Decimal.negative?(low) ->
        {:error, Errors.negative_price(:low, low)}

      Decimal.negative?(close) ->
        {:error, Errors.negative_price(:close, close)}

      Decimal.gt?(low, high) ->
        {:error,
         %Errors.ValidationError{
           message: "Low price cannot be greater than high price",
           field: :low,
           value: {low, high},
           constraint: "low <= high"
         }}

      true ->
        :ok
    end
  end

  defp validate_hlc_fields(data_point) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "VWAP requires high, low, close fields as Decimals",
       expected: "map with :high, :low, :close keys as Decimals",
       received: inspect(data_point)
     }}
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_vwap_values([], _variant, _session_reset), do: {:ok, []}

  defp calculate_vwap_values(data, variant, session_reset) do
    {results, _final_state} =
      data
      |> Enum.reduce({[], nil}, fn data_point, {acc_results, state} ->
        # Initialize state on first iteration
        current_state =
          state ||
            %{
              variant: variant,
              session_reset: session_reset,
              cumulative_price_volume: Decimal.new("0"),
              cumulative_volume: Decimal.new("0"),
              current_session_start: nil,
              count: 0
            }

        # Update state with current data point
        case update_state(current_state, data_point) do
          {:ok, new_state, result} when result != nil ->
            {[result | acc_results], new_state}

          {:ok, new_state, nil} ->
            # Zero volume period, no result
            {acc_results, new_state}

          {:error, _error} ->
            # Skip invalid data points
            {acc_results, current_state}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  defp calculate_price_by_variant(data_point, :close), do: data_point.close

  defp calculate_price_by_variant(%{high: high, low: low, close: close}, :typical) do
    # Typical Price = (High + Low + Close) / 3
    sum = Decimal.add(high, Decimal.add(low, close))
    Decimal.div(sum, Decimal.new("3"))
  end

  defp calculate_price_by_variant(%{high: high, low: low, close: close}, :weighted) do
    # Weighted Price = (High + Low + 2*Close) / 4
    close_x2 = Decimal.mult(close, Decimal.new("2"))
    sum = Decimal.add(high, Decimal.add(low, close_x2))
    Decimal.div(sum, Decimal.new("4"))
  end

  defp should_reset_session?(:none, _session_start, _timestamp), do: false
  defp should_reset_session?(_reset_type, nil, _timestamp), do: false

  defp should_reset_session?(reset_type, session_start, timestamp) do
    case reset_type do
      :daily ->
        Date.diff(DateTime.to_date(timestamp), DateTime.to_date(session_start)) > 0

      :weekly ->
        weeks_diff = div(Date.diff(DateTime.to_date(timestamp), DateTime.to_date(session_start)), 7)
        weeks_diff > 0

      :monthly ->
        timestamp.year > session_start.year or
          (timestamp.year == session_start.year and timestamp.month > session_start.month)

      _ ->
        false
    end
  end

  defp get_session_start(:none, timestamp), do: timestamp

  defp get_session_start(:daily, timestamp) do
    # Start of day
    %{timestamp | hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
  end

  defp get_session_start(:weekly, timestamp) do
    # Start of week (Monday)
    date = DateTime.to_date(timestamp)
    days_to_subtract = Date.day_of_week(date) - 1
    start_date = Date.add(date, -days_to_subtract)
    DateTime.new!(start_date, ~T[00:00:00.000000])
  end

  defp get_session_start(:monthly, timestamp) do
    # Start of month
    date = DateTime.to_date(timestamp)
    start_date = %{date | day: 1}
    DateTime.new!(start_date, ~T[00:00:00.000000])
  end
end
