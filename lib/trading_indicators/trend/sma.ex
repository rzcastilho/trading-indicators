defmodule TradingIndicators.Trend.SMA do
  @moduledoc """
  Simple Moving Average (SMA) indicator implementation.

  The Simple Moving Average calculates the arithmetic mean of a specified number
  of closing prices over a given period. It's one of the most basic and widely 
  used trend-following indicators.

  ## Formula

  SMA = (P1 + P2 + ... + Pn) / n

  Where:
  - P1, P2, ..., Pn are the closing prices for the last n periods
  - n is the period (number of time periods)

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Trend.SMA.calculate(data, period: 3)
      iex> [first, second] = result
      iex> Decimal.round(first.value, 2)
      Decimal.new("102.00")
      iex> Decimal.round(second.value, 2)
      Decimal.new("103.00")

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, must be >= 1)
  - `:source` - Source field to use: `:open`, `:high`, `:low`, `:close`, or `:volume` (default: `:close`)

  ## Notes

  - Requires at least `period` number of data points
  - Returns results only when sufficient data is available
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20

  @doc """
  Calculates Simple Moving Average for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:source` - Source field: `:open`, `:high`, `:low`, `:close`, or `:volume` (default: `:close`)

  ## Returns

  - `{:ok, results}` - List of SMA calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = SMA.calculate(data, period: 2)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, :close),
         :ok <- Utils.validate_data_length(data, period) do
      prices = extract_prices(data, source)
      calculate_sma_values(prices, period, data)
    end
  end

  @doc """
  Validates parameters for SMA calculation.

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
  Returns the minimum number of periods required for SMA calculation.

  ## Returns

  - Default period if no options provided
  - Configured period from options

  ## Example

      iex> TradingIndicators.Trend.SMA.required_periods()
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

      iex> TradingIndicators.Trend.SMA.required_periods(period: 14)
      14
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Returns metadata describing all parameters accepted by the SMA indicator.

  ## Returns

  - List of parameter metadata maps

  ## Example

      iex> TradingIndicators.Trend.SMA.parameter_metadata()
      [
        %TradingIndicators.Types.ParamMetadata{
          name: :period,
          type: :integer,
          default: 20,
          required: false,
          min: 1,
          max: nil,
          options: nil,
          description: "Number of periods to use in SMA calculation"
        },
        %TradingIndicators.Types.ParamMetadata{
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
        description: "Number of periods to use in SMA calculation"
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
  Returns metadata describing the output fields for SMA.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Trend.SMA.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description: "Simple Moving Average - arithmetic mean of prices over a period",
      example: "sma_20 > close"
    }
  end

  @doc """
  Initializes streaming state for real-time SMA calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = SMA.init_state(period: 14)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)

    %{
      period: period,
      source: source,
      prices: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, sma_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = SMA.init_state(period: 3)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = SMA.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{period: period, source: source, prices: prices, count: count} = _state,
        data_point
      ) do
    try do
      price = extract_single_price(data_point, source)
      new_prices = update_price_buffer(prices, price, period)
      new_count = count + 1

      new_state = %{
        period: period,
        source: source,
        prices: new_prices,
        count: new_count
      }

      if new_count >= period do
        sma_value = Utils.mean(new_prices)
        timestamp = get_timestamp(data_point)

        result = %{
          value: sma_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "SMA",
            period: period,
            source: source
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
       message: "Invalid state format for SMA streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
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

  defp extract_ohlcv_prices(data, :volume), do: Utils.extract_volumes_as_decimal(data)

  defp extract_single_price(%{} = data_point, :volume),
    do: Utils.extract_volume_as_decimal(data_point)

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

  defp calculate_sma_values(prices, period, original_data) do
    results =
      prices
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {window, index} ->
        sma_value = Utils.mean(window)
        timestamp = get_data_timestamp(original_data, index)

        %{
          value: sma_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "SMA",
            period: period,
            source: :close
          }
        }
      end)

    {:ok, results}
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

  defp update_price_buffer(prices, new_price, period) do
    updated_prices = prices ++ [new_price]

    if length(updated_prices) > period do
      # Take last N elements
      Enum.take(updated_prices, -period)
    else
      updated_prices
    end
  end
end
