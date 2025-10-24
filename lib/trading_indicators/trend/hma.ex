defmodule TradingIndicators.Trend.HMA do
  @moduledoc """
  Hull Moving Average (HMA) indicator implementation.

  The Hull Moving Average (HMA), developed by Alan Hull, is a very responsive
  moving average that almost eliminates lag while maintaining smoothness.
  It uses weighted moving averages and square root periods to achieve this.

  ## Formula

  1. Calculate WMA with period n/2 and multiply by 2
  2. Calculate WMA with period n  
  3. Raw HMA = (2 × WMA(n/2)) - WMA(n)
  4. Final HMA = WMA of Raw HMA values with period sqrt(n)

  Where:
  - n is the period
  - WMA is Weighted Moving Average
  - sqrt(n) is the square root of the period (rounded)

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
      ...>   %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:34:00Z]},
      ...>   %{close: Decimal.new("107"), timestamp: ~U[2024-01-01 09:35:00Z]},
      ...>   %{close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:36:00Z]},
      ...>   %{close: Decimal.new("108"), timestamp: ~U[2024-01-01 09:37:00Z]},
      ...>   %{close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:38:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Trend.HMA.calculate(data, period: 4)
      iex> length(result) >= 1
      true

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, must be >= 2)
  - `:source` - Source price field to use (default: `:close`)

  ## Notes

  - Much more responsive to price changes than traditional moving averages
  - Significantly reduces lag while maintaining smoothness
  - Requires at least `period + sqrt(period)` data points for full calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates with some complexity
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  alias TradingIndicators.Trend.WMA
  require Decimal

  @default_period 14

  @doc """
  Calculates Hull Moving Average for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:source` - Price source (default: `:close`)

  ## Returns

  - `{:ok, results}` - List of HMA calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = HMA.calculate(data, period: 4)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, :close),
         sqrt_period <- calculate_sqrt_period(period),
         # Conservative estimate
         min_required <- period + sqrt_period - 1,
         :ok <- Utils.validate_data_length(data, min_required) do
      calculate_hma_values(data, period, source, sqrt_period)
    end
  end

  @doc """
  Validates parameters for HMA calculation.

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

    with :ok <- validate_period(period),
         :ok <- validate_source(source) do
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
  Returns the minimum number of periods required for HMA calculation.

  ## Returns

  - Default period + sqrt(period) - 1

  ## Example

      iex> TradingIndicators.Trend.HMA.required_periods()
      17
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods do
    period = @default_period
    sqrt_period = calculate_sqrt_period(period)
    period + sqrt_period - 1
  end

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods (period + sqrt(period) - 1)

  ## Example

      iex> TradingIndicators.Trend.HMA.required_periods(period: 9)
      11
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    sqrt_period = calculate_sqrt_period(period)
    period + sqrt_period - 1
  end

  @doc """
  Returns metadata describing all parameters accepted by the Hull Moving Average indicator.

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
        min: 2,
        max: nil,
        options: nil,
        description: "Number of periods to use in calculation"
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
  Initializes streaming state for real-time HMA calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = HMA.init_state(period: 9)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)
    half_period = div(period, 2)
    sqrt_period = calculate_sqrt_period(period)

    %{
      period: period,
      half_period: half_period,
      sqrt_period: sqrt_period,
      source: source,
      wma_half_state: WMA.init_state(period: half_period, source: source),
      wma_full_state: WMA.init_state(period: period, source: source),
      # For HMA raw values
      wma_sqrt_state: WMA.init_state(period: sqrt_period, source: :close),
      raw_hma_values: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, hma_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = HMA.init_state(period: 4)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = HMA.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          half_period: half_period,
          sqrt_period: sqrt_period,
          source: source,
          wma_half_state: wma_half_state,
          wma_full_state: wma_full_state,
          wma_sqrt_state: wma_sqrt_state,
          raw_hma_values: raw_hma_values,
          count: count
        } = _state,
        data_point
      ) do
    try do
      new_count = count + 1

      # Update both WMA states
      {:ok, new_wma_half_state, wma_half_result} = WMA.update_state(wma_half_state, data_point)
      {:ok, new_wma_full_state, wma_full_result} = WMA.update_state(wma_full_state, data_point)

      case {wma_half_result, wma_full_result} do
        {%{value: half_wma}, %{value: full_wma}} ->
          # Calculate raw HMA: (2 × WMA(n/2)) - WMA(n)
          raw_hma = Decimal.sub(Decimal.mult(half_wma, Decimal.new("2")), full_wma)

          # Create synthetic data point for sqrt WMA calculation
          timestamp = get_timestamp(data_point)
          raw_hma_data_point = %{close: raw_hma, timestamp: timestamp}

          # Update sqrt WMA state with raw HMA value
          {:ok, new_wma_sqrt_state, sqrt_result} =
            WMA.update_state(wma_sqrt_state, raw_hma_data_point)

          new_raw_hma_values = update_raw_hma_buffer(raw_hma_values, raw_hma, sqrt_period)

          new_state = %{
            period: period,
            half_period: half_period,
            sqrt_period: sqrt_period,
            source: source,
            wma_half_state: new_wma_half_state,
            wma_full_state: new_wma_full_state,
            wma_sqrt_state: new_wma_sqrt_state,
            raw_hma_values: new_raw_hma_values,
            count: new_count
          }

          if sqrt_result do
            # Final HMA is ready
            result = %{
              value: sqrt_result.value,
              timestamp: timestamp,
              metadata: %{
                indicator: "HMA",
                period: period,
                source: source
              }
            }

            {:ok, new_state, result}
          else
            {:ok, new_state, nil}
          end

        _ ->
          # Not enough data for HMA calculation yet
          new_state = %{
            period: period,
            half_period: half_period,
            sqrt_period: sqrt_period,
            source: source,
            wma_half_state: new_wma_half_state,
            wma_full_state: new_wma_full_state,
            # Unchanged since no raw HMA yet
            wma_sqrt_state: wma_sqrt_state,
            raw_hma_values: raw_hma_values,
            count: new_count
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
       message: "Invalid state format for HMA streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 2, do: :ok

  defp validate_period(period) do
    {:error,
     %Errors.InvalidParams{
       message: "HMA period must be at least 2, got #{inspect(period)}",
       param: :period,
       value: period,
       expected: "integer >= 2"
     }}
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

  defp calculate_sqrt_period(period) do
    # Calculate square root and round to nearest integer
    sqrt_value = :math.sqrt(period)
    round(sqrt_value)
  end

  defp calculate_hma_values(data, period, source, sqrt_period) do
    half_period = div(period, 2)

    # Calculate the two WMAs
    with {:ok, wma_half_results} <- WMA.calculate(data, period: half_period, source: source),
         {:ok, wma_full_results} <- WMA.calculate(data, period: period, source: source) do
      # Align the WMA results by timestamp
      aligned_wmas = align_wma_results(wma_half_results, wma_full_results)

      # Calculate raw HMA values
      raw_hma_values = calculate_raw_hma_values(aligned_wmas)

      # Apply final WMA with sqrt period to raw HMA values
      case WMA.calculate(raw_hma_values, period: sqrt_period, source: :close) do
        {:ok, hma_results} ->
          # Convert to proper HMA result format
          final_results =
            Enum.map(hma_results, fn result ->
              %{
                result
                | value: result.value,
                  metadata: %{
                    indicator: "HMA",
                    period: period,
                    source: source
                  }
              }
            end)

          {:ok, final_results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp align_wma_results(wma_half_results, wma_full_results) do
    # Create map for half WMA lookup by timestamp
    half_map = Map.new(wma_half_results, fn result -> {result.timestamp, result.value} end)

    # Find matching timestamps in full WMA results
    wma_full_results
    |> Enum.filter(fn full_result ->
      Map.has_key?(half_map, full_result.timestamp)
    end)
    |> Enum.map(fn full_result ->
      half_value = Map.get(half_map, full_result.timestamp)
      {half_value, full_result.value, full_result.timestamp}
    end)
  end

  defp calculate_raw_hma_values(aligned_wmas) do
    Enum.map(aligned_wmas, fn {half_wma, full_wma, timestamp} ->
      # Raw HMA = (2 × WMA(n/2)) - WMA(n)
      raw_hma = Decimal.sub(Decimal.mult(half_wma, Decimal.new("2")), full_wma)

      %{
        close: raw_hma,
        timestamp: timestamp
      }
    end)
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp update_raw_hma_buffer(values, new_value, max_size) do
    updated_values = values ++ [new_value]

    if length(updated_values) > max_size do
      Enum.take(updated_values, -max_size)
    else
      updated_values
    end
  end
end
