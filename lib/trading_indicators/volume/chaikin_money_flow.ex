defmodule TradingIndicators.Volume.ChaikinMoneyFlow do
  @moduledoc """
  Chaikin Money Flow (CMF) indicator implementation.

  Chaikin Money Flow is a technical analysis indicator created by Marc Chaikin that
  combines price and volume data to measure the flow of money into and out of a
  security over a specific period. Unlike the Accumulation/Distribution Line (which
  is cumulative), CMF is an oscillator that measures money flow over a rolling period.

  ## Formula

  1. Money Flow Multiplier = ((Close - Low) - (High - Close)) / (High - Low)
  2. Money Flow Volume = Money Flow Multiplier × Volume
  3. CMF = Sum(Money Flow Volume, period) / Sum(Volume, period)

  ## Special Cases

  - When High = Low (no price range), Money Flow Multiplier = 0
  - When period volume sum is zero, CMF = 0
  - Requires at least `period` data points for calculation

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{high: Decimal.new("108"), low: Decimal.new("104"), close: Decimal.new("105"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volume.ChaikinMoneyFlow.calculate(data, period: 2)
      iex> [first | _] = result
      iex> Decimal.round(first.value, 4)
      Decimal.new("0.4933")

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, default: 20, must be >= 1)

  ## Usage Notes

  - Returns results only when sufficient data is available (period + 1 or more points)
  - Requires OHLCV data with High, Low, Close, and Volume
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Volume must be non-negative
  - CMF oscillates between -1 and +1

  ## Interpretation

  - **CMF > 0** - Money flowing into the security (accumulation/buying pressure)
  - **CMF < 0** - Money flowing out of the security (distribution/selling pressure)
  - **CMF near 0** - Balanced money flow or low trading activity
  - **Strong values** - CMF near +1 (strong buying) or -1 (strong selling)
  - **Trend confirmation** - CMF direction confirms price trend direction
  - **Divergence** - CMF moving opposite to price can signal potential reversal
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20

  @doc """
  Calculates Chaikin Money Flow for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires HLCV)
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})

  ## Returns

  - `{:ok, results}` - List of CMF calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = ChaikinMoneyFlow.calculate(data, period: 14)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         :ok <- Utils.validate_data_length(data, period),
         :ok <- validate_ohlcv_data(data) do
      calculate_cmf_values(data, period)
    end
  end

  @doc """
  Validates parameters for CMF calculation.

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
    validate_period(period)
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
  Returns the minimum number of periods required for CMF calculation.

  ## Returns

  - Default period if no options provided

  ## Example

      iex> TradingIndicators.Volume.ChaikinMoneyFlow.required_periods()
      20
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

      iex> TradingIndicators.Volume.ChaikinMoneyFlow.required_periods(period: 14)
      14
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Returns metadata describing all parameters accepted by the Chaikin Money Flow indicator.

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
        description: "Number of periods to use in calculation"
      }
    ]
  end

  @doc """
  Returns metadata describing the output fields for Chaikin Money Flow.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Volume.ChaikinMoneyFlow.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description: "Chaikin Money Flow - volume-weighted indicator measuring buying and selling pressure",
      example: "cmf_20 > 0.05 or cmf_20 < -0.05",
      unit: "%"
    }
  end

  @doc """
  Initializes streaming state for real-time CMF calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = ChaikinMoneyFlow.init_state(period: 14)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)

    %{
      period: period,
      money_flow_volumes: [],
      volumes: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, cmf_result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = ChaikinMoneyFlow.init_state(period: 3)
      data_point = %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = ChaikinMoneyFlow.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{period: period, money_flow_volumes: mf_volumes, volumes: volumes, count: count} = _state,
        %{high: high, low: low, close: close, volume: volume} = data_point
      ) do
    try do
      # Validate the data point
      with :ok <- validate_single_ohlcv_data(data_point) do
        new_count = count + 1

        # Calculate Money Flow Volume for current data point
        {_mf_multiplier, mf_volume} = calculate_money_flow(high, low, close, volume)
        volume_decimal = Decimal.new(volume)

        # Update buffers with new values
        new_mf_volumes = update_buffer(mf_volumes, mf_volume, period)
        new_volumes = update_buffer(volumes, volume_decimal, period)

        new_state = %{
          period: period,
          money_flow_volumes: new_mf_volumes,
          volumes: new_volumes,
          count: new_count
        }

        if new_count >= period do
          # Calculate CMF
          mf_sum = Enum.reduce(new_mf_volumes, Decimal.new("0"), &Decimal.add/2)
          volume_sum = Enum.reduce(new_volumes, Decimal.new("0"), &Decimal.add/2)

          cmf_value =
            if Decimal.positive?(volume_sum) do
              Decimal.div(mf_sum, volume_sum)
            else
              Decimal.new("0")
            end

          result = %{
            value: cmf_value,
            timestamp: get_timestamp(data_point),
            metadata: %{
              indicator: "ChaikinMoneyFlow",
              period: period,
              money_flow_volume_sum: mf_sum,
              volume_sum: volume_sum,
              current_money_flow_volume: mf_volume,
              volume: volume,
              close: close,
              high: high,
              low: low
            }
          }

          {:ok, new_state, result}
        else
          {:ok, new_state, nil}
        end
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message:
         "Invalid state format for ChaikinMoneyFlow streaming or data point missing HLCV fields",
       operation: :update_state,
       reason: "malformed state or invalid data point"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
  end

  defp validate_ohlcv_data([]), do: :ok

  defp validate_ohlcv_data([
         %{high: high, low: low, close: close, volume: volume} = data_point | rest
       ]) do
    with :ok <- validate_hlcv_fields(high, low, close, volume, data_point) do
      validate_ohlcv_data(rest)
    end
  end

  defp validate_ohlcv_data([invalid | _rest]) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "ChaikinMoneyFlow requires data with high, low, close, and volume fields",
       expected: "map with :high, :low, :close, :volume keys",
       received: inspect(invalid)
     }}
  end

  defp validate_single_ohlcv_data(
         %{high: high, low: low, close: close, volume: volume} = data_point
       ) do
    validate_hlcv_fields(high, low, close, volume, data_point)
  end

  defp validate_single_ohlcv_data(invalid) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "ChaikinMoneyFlow requires data with high, low, close, and volume fields",
       expected: "map with :high, :low, :close, :volume keys",
       received: inspect(invalid)
     }}
  end

  defp validate_hlcv_fields(high, low, close, volume, data_point) do
    with :ok <- validate_price_field(high, :high, data_point),
         :ok <- validate_price_field(low, :low, data_point),
         :ok <- validate_price_field(close, :close, data_point),
         :ok <- validate_volume(volume, data_point),
         :ok <- validate_price_relationship(high, low, data_point) do
      :ok
    end
  end

  defp validate_price_field(price, field, _data_point) when is_struct(price, Decimal) do
    if Decimal.negative?(price) do
      {:error, Errors.negative_price(field, price)}
    else
      :ok
    end
  end

  defp validate_price_field(price, field, data_point) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "#{String.capitalize(to_string(field))} price must be a Decimal",
       expected: "Decimal.t()",
       received: "#{inspect(price)} in #{inspect(data_point)}"
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

  defp validate_price_relationship(high, low, _data_point) do
    if Decimal.gt?(low, high) do
      {:error,
       %Errors.ValidationError{
         message: "Low price cannot be greater than high price",
         field: :price_relationship,
         value: {low, high},
         constraint: "low <= high"
       }}
    else
      :ok
    end
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_cmf_values(data, period) when length(data) < period do
    {:ok, []}
  end

  defp calculate_cmf_values(data, period) do
    # Calculate Money Flow Volume for each data point
    money_flow_data =
      Enum.map(data, fn data_point ->
        {_mf_multiplier, mf_volume} =
          calculate_money_flow(
            data_point.high,
            data_point.low,
            data_point.close,
            data_point.volume
          )

        {data_point, mf_volume, Decimal.new(data_point.volume)}
      end)

    # Calculate CMF using sliding window
    results =
      money_flow_data
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {window, _index} ->
        # Sum Money Flow Volumes and Volumes for the period
        {mf_sum, volume_sum} =
          window
          |> Enum.reduce({Decimal.new("0"), Decimal.new("0")}, fn {_data_point, mf_vol, vol},
                                                                  {mf_acc, vol_acc} ->
            {Decimal.add(mf_acc, mf_vol), Decimal.add(vol_acc, vol)}
          end)

        # Calculate CMF
        cmf_value =
          if Decimal.positive?(volume_sum) do
            Decimal.div(mf_sum, volume_sum)
          else
            Decimal.new("0")
          end

        # Get the current data point for metadata and timestamp
        {current_data_point, current_mf_volume, _current_volume} = List.last(window)

        %{
          value: cmf_value,
          timestamp: get_timestamp(current_data_point),
          metadata: %{
            indicator: "ChaikinMoneyFlow",
            period: period,
            money_flow_volume_sum: mf_sum,
            volume_sum: volume_sum,
            current_money_flow_volume: current_mf_volume,
            volume: current_data_point.volume,
            close: current_data_point.close,
            high: current_data_point.high,
            low: current_data_point.low
          }
        }
      end)

    {:ok, results}
  end

  defp calculate_money_flow(high, low, close, volume) do
    volume_decimal = Decimal.new(volume)

    # Handle special case where High = Low (no price range)
    if Decimal.equal?(high, low) do
      # Money Flow Multiplier = 0 when there's no price range
      mf_multiplier = Decimal.new("0")
      mf_volume = Decimal.new("0")
      {mf_multiplier, mf_volume}
    else
      # Money Flow Multiplier = ((Close - Low) - (High - Close)) / (High - Low)
      close_minus_low = Decimal.sub(close, low)
      high_minus_close = Decimal.sub(high, close)
      numerator = Decimal.sub(close_minus_low, high_minus_close)
      denominator = Decimal.sub(high, low)

      mf_multiplier = Decimal.div(numerator, denominator)
      mf_volume = Decimal.mult(mf_multiplier, volume_decimal)

      {mf_multiplier, mf_volume}
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
end
