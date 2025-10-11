defmodule TradingIndicators.Volume.AccumulationDistribution do
  @moduledoc """
  Accumulation/Distribution Line (A/D Line) indicator implementation.

  The Accumulation/Distribution Line is a volume-based indicator designed to measure
  the cumulative flow of money into and out of a security. It was developed by 
  Marc Chaikin and combines price and volume to assess whether a stock is being
  accumulated (bought) or distributed (sold).

  ## Formula

  1. Money Flow Multiplier = ((Close - Low) - (High - Close)) / (High - Low)
  2. Money Flow Volume = Money Flow Multiplier × Volume
  3. A/D Line = Previous A/D Line + Money Flow Volume

  ## Special Cases

  - When High = Low (no price range), Money Flow Multiplier = 0
  - First data point initializes A/D Line to Money Flow Volume
  - Accumulates over entire data series (cumulative indicator)

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volume.AccumulationDistribution.calculate(data, [])
      iex> [first | _] = result
      iex> Decimal.round(first.value, 0)
      Decimal.new("333")

  ## Usage Notes

  - Returns results for all data points
  - Requires OHLCV data with High, Low, Close, and Volume
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Volume must be non-negative
  - Handles price gaps and equal high/low scenarios

  ## Interpretation

  - **Rising A/D Line** - Accumulation (buying pressure) is dominant
  - **Falling A/D Line** - Distribution (selling pressure) is dominant
  - **Divergence from Price** - Can signal potential trend reversal
  - **Confirmation** - A/D Line moving with price confirms trend
  - **Volume Validation** - Incorporates volume to validate price movements
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @doc """
  Calculates Accumulation/Distribution Line for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires HLCV)
  - `opts` - Calculation options (keyword list) - currently no options supported

  ## Returns

  - `{:ok, results}` - List of A/D Line calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      ]
      {:ok, result} = AccumulationDistribution.calculate(data, [])
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         :ok <- Utils.validate_data_length(data, 1),
         :ok <- validate_ohlcv_data(data) do
      calculate_ad_values(data)
    end
  end

  @doc """
  Validates parameters for A/D Line calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    # A/D Line currently doesn't accept any parameters
    if Enum.empty?(opts) do
      :ok
    else
      # Check for unsupported parameters
      unsupported_keys = Keyword.keys(opts)

      {:error,
       %Errors.InvalidParams{
         message:
           "AccumulationDistribution does not accept parameters. Unsupported keys: #{inspect(unsupported_keys)}",
         param: :unsupported_params,
         value: unsupported_keys,
         expected: "empty options list"
       }}
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
  Returns the minimum number of periods required for A/D Line calculation.

  ## Returns

  - Always 1 (A/D Line can be calculated from the first data point)

  ## Example

      iex> TradingIndicators.Volume.AccumulationDistribution.required_periods()
      1
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: 1

  @doc """
  Initializes streaming state for real-time A/D Line calculation.

  ## Parameters

  - `opts` - Configuration options (currently unused)

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = AccumulationDistribution.init_state([])
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    # Suppress unused warning
    _ = opts

    %{
      ad_line_value: nil,
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, ad_result}` - Updated state with result
  - `{:error, reason}` - Error occurred

  ## Example

      state = AccumulationDistribution.init_state([])
      data_point = %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = AccumulationDistribution.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{ad_line_value: ad_line_value, count: count} = _state,
        %{high: high, low: low, close: close, volume: volume} = data_point
      ) do
    try do
      # Validate the data point
      with :ok <- validate_single_ohlcv_data(data_point) do
        new_count = count + 1

        # Calculate Money Flow Multiplier and Money Flow Volume
        {mf_multiplier, mf_volume} = calculate_money_flow(high, low, close, volume)

        # Calculate new A/D Line value
        new_ad_value =
          if ad_line_value do
            Decimal.add(ad_line_value, mf_volume)
          else
            # First data point: A/D Line starts with Money Flow Volume
            mf_volume
          end

        new_state = %{
          ad_line_value: new_ad_value,
          count: new_count
        }

        result = %{
          value: new_ad_value,
          timestamp: get_timestamp(data_point),
          metadata: %{
            indicator: "AccumulationDistribution",
            money_flow_multiplier: mf_multiplier,
            money_flow_volume: mf_volume,
            volume: volume,
            close: close,
            high: high,
            low: low
          }
        }

        {:ok, new_state, result}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message:
         "Invalid state format for AccumulationDistribution streaming or data point missing HLCV fields",
       operation: :update_state,
       reason: "malformed state or invalid data point"
     }}
  end

  # Private functions

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
       message: "AccumulationDistribution requires data with high, low, close, and volume fields",
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
       message: "AccumulationDistribution requires data with high, low, close, and volume fields",
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

  defp calculate_ad_values([]), do: {:ok, []}

  defp calculate_ad_values([first_data | rest_data]) do
    # Calculate first A/D Line value (starts with Money Flow Volume)
    {first_mf_multiplier, first_mf_volume} =
      calculate_money_flow(
        first_data.high,
        first_data.low,
        first_data.close,
        first_data.volume
      )

    first_result = %{
      value: first_mf_volume,
      timestamp: get_timestamp(first_data),
      metadata: %{
        indicator: "AccumulationDistribution",
        money_flow_multiplier: first_mf_multiplier,
        money_flow_volume: first_mf_volume,
        volume: first_data.volume,
        close: first_data.close,
        high: first_data.high,
        low: first_data.low
      }
    }

    # Process remaining data points
    {final_results, _final_ad} =
      rest_data
      |> Enum.reduce({[first_result], first_mf_volume}, fn current_data, {acc_results, prev_ad} ->
        # Calculate Money Flow for current data point
        {mf_multiplier, mf_volume} =
          calculate_money_flow(
            current_data.high,
            current_data.low,
            current_data.close,
            current_data.volume
          )

        # Calculate new A/D Line value
        new_ad = Decimal.add(prev_ad, mf_volume)

        result = %{
          value: new_ad,
          timestamp: get_timestamp(current_data),
          metadata: %{
            indicator: "AccumulationDistribution",
            money_flow_multiplier: mf_multiplier,
            money_flow_volume: mf_volume,
            volume: current_data.volume,
            close: current_data.close,
            high: current_data.high,
            low: current_data.low
          }
        }

        {[result | acc_results], new_ad}
      end)

    {:ok, Enum.reverse(final_results)}
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
end
