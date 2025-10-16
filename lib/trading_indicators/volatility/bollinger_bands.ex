defmodule TradingIndicators.Volatility.BollingerBands do
  @moduledoc """
  Bollinger Bands volatility indicator implementation.

  Bollinger Bands are a technical analysis tool created by John Bollinger. They consist 
  of a middle band (Simple Moving Average) and an upper and lower band that are standard
  deviations away from the middle band. The bands provide a relative definition of high 
  and low prices.

  ## Formula

  Middle Band = SMA(close, period)
  Upper Band = Middle Band + (multiplier × Standard Deviation)
  Lower Band = Middle Band - (multiplier × Standard Deviation)

  %B = (Close - Lower Band) / (Upper Band - Lower Band) × 100
  Bandwidth = (Upper Band - Lower Band) / Middle Band × 100

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
      ...>   %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:34:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volatility.BollingerBands.calculate(data, period: 3, multiplier: 2)
      iex> [_first, second, _third | _] = result
      iex> Decimal.round(second.upper_band, 2)
      Decimal.new("105.00")

  ## Parameters

  - `:period` - Number of periods for SMA and Standard Deviation (required, must be >= 2)
  - `:multiplier` - Standard deviation multiplier (default: 2.0)
  - `:source` - Source price field to use (default: `:close`)

  ## Notes

  - Requires at least `period` number of data points
  - Returns results only when sufficient data is available
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - %B values above 100 indicate price is above upper band
  - %B values below 0 indicate price is below lower band
  - Bandwidth measures the distance between upper and lower bands
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20
  @default_multiplier Decimal.new("2.0")

  @doc """
  Calculates Bollinger Bands for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:multiplier` - Standard deviation multiplier (default: 2.0)
  - `:source` - Price source (default: `:close`)

  ## Returns

  - `{:ok, results}` - List of Bollinger Bands calculations
  - `{:error, reason}` - Error if calculation fails

  ## Result Structure

  Each result contains:
  - `:upper_band` - Upper Bollinger Band
  - `:middle_band` - Middle Band (SMA)
  - `:lower_band` - Lower Bollinger Band
  - `:percent_b` - %B oscillator value
  - `:bandwidth` - Bandwidth measurement
  - `:timestamp` - Data point timestamp
  - `:metadata` - Calculation metadata

  ## Example

      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:ok, result} = BollingerBands.calculate(data, period: 20, multiplier: 2.0)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, [Types.bollinger_result()]} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         multiplier <- get_multiplier(opts),
         source <- Keyword.get(opts, :source, :close),
         :ok <- Utils.validate_data_length(data, period) do
      prices = extract_prices(data, source)
      calculate_bollinger_values(prices, period, multiplier, source, data)
    end
  end

  @doc """
  Validates parameters for Bollinger Bands calculation.

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
    multiplier = get_multiplier(opts)
    source = Keyword.get(opts, :source, :close)

    with :ok <- validate_period(period),
         :ok <- validate_multiplier(multiplier),
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
  Returns the minimum number of periods required for Bollinger Bands calculation.

  ## Returns

  - Default period if no options provided

  ## Example

      iex> TradingIndicators.Volatility.BollingerBands.required_periods()
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

      iex> TradingIndicators.Volatility.BollingerBands.required_periods(period: 14)
      14
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Returns metadata describing all parameters accepted by the Bollinger Bands indicator.

  ## Returns

  - List of parameter metadata maps

  ## Example

      iex> metadata = TradingIndicators.Volatility.BollingerBands.parameter_metadata()
      iex> Enum.any?(metadata, fn param -> param.name == :multiplier end)
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
        min: 2,
        max: nil,
        options: nil,
        description: "Number of periods for SMA and Standard Deviation"
      },
      %Types.ParamMetadata{
        name: :multiplier,
        type: :float,
        default: 2.0,
        required: false,
        min: 0.0,
        max: nil,
        options: nil,
        description: "Standard deviation multiplier for bands"
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
  Initializes streaming state for real-time Bollinger Bands calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = BollingerBands.init_state(period: 20, multiplier: 2.0)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    multiplier = get_multiplier(opts)
    source = Keyword.get(opts, :source, :close)

    %{
      period: period,
      multiplier: multiplier,
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

  - `{:ok, new_state, bollinger_result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = BollingerBands.init_state(period: 3)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = BollingerBands.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.bollinger_result() | nil} | {:error, term()}
  def update_state(
        %{period: period, multiplier: multiplier, source: source, prices: prices, count: count} =
          _state,
        data_point
      ) do
    try do
      price = extract_single_price(data_point, source)
      new_prices = update_price_buffer(prices, price, period)
      new_count = count + 1

      new_state = %{
        period: period,
        multiplier: multiplier,
        source: source,
        prices: new_prices,
        count: new_count
      }

      if new_count >= period do
        bollinger_result = calculate_single_bollinger(new_prices, multiplier, price)
        timestamp = get_timestamp(data_point)

        result = Map.put(bollinger_result, :timestamp, timestamp)

        result =
          Map.put(result, :metadata, %{
            indicator: "BOLLINGER",
            period: period,
            multiplier: multiplier,
            source: source
          })

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
       message: "Invalid state format for BollingerBands streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 2, do: :ok

  defp validate_period(period) do
    {:error,
     %Errors.InvalidParams{
       message:
         "Period must be an integer >= 2 for Bollinger Bands calculation, got: #{inspect(period)}",
       param: :period,
       value: period,
       expected: "integer >= 2"
     }}
  end

  defp validate_multiplier(%Decimal{} = multiplier) do
    if Decimal.positive?(multiplier) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         message: "Multiplier must be a positive number, got: #{inspect(multiplier)}",
         param: :multiplier,
         value: multiplier,
         expected: "positive Decimal"
       }}
    end
  end

  defp validate_multiplier(multiplier) when is_number(multiplier) and multiplier > 0, do: :ok

  defp validate_multiplier(multiplier) do
    {:error,
     %Errors.InvalidParams{
       message: "Multiplier must be a positive number, got: #{inspect(multiplier)}",
       param: :multiplier,
       value: multiplier,
       expected: "positive number"
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

  defp get_multiplier(opts) do
    case Keyword.get(opts, :multiplier, @default_multiplier) do
      %Decimal{} = multiplier -> multiplier
      multiplier when is_float(multiplier) -> Decimal.from_float(multiplier)
      multiplier when is_integer(multiplier) -> Decimal.new(multiplier)
      # Let validation handle it
      multiplier -> multiplier
    end
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

  defp extract_single_price(%Decimal{} = price, _source) do
    price
  end

  defp extract_single_price(price, _source) when is_number(price) do
    Decimal.new(price)
  end

  defp extract_single_price(%{} = data_point, source) do
    Map.fetch!(data_point, source)
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_bollinger_values(prices, period, multiplier, source, original_data) do
    results =
      prices
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {window, index} ->
        current_price = Enum.at(prices, index)
        bollinger_result = calculate_single_bollinger(window, multiplier, current_price)
        timestamp = get_data_timestamp(original_data, index)

        bollinger_result
        |> Map.put(:timestamp, timestamp)
        |> Map.put(:metadata, %{
          indicator: "BOLLINGER",
          period: period,
          multiplier: multiplier,
          source: source
        })
      end)

    {:ok, results}
  end

  defp calculate_single_bollinger(prices, multiplier, current_price) do
    # Calculate middle band (SMA)
    middle_band = Utils.mean(prices)

    # Calculate standard deviation
    std_dev = Utils.standard_deviation(prices)

    # Calculate upper and lower bands
    deviation = Decimal.mult(multiplier, std_dev)
    upper_band = Decimal.add(middle_band, deviation)
    lower_band = Decimal.sub(middle_band, deviation)

    # Calculate %B
    band_range = Decimal.sub(upper_band, lower_band)

    percent_b =
      if Decimal.equal?(band_range, Decimal.new("0")) do
        # Middle value when bands collapse
        Decimal.new("50.0")
      else
        price_from_lower = Decimal.sub(current_price, lower_band)
        ratio = Decimal.div(price_from_lower, band_range)
        Decimal.mult(ratio, Decimal.new("100"))
      end

    # Calculate Bandwidth
    bandwidth =
      if Decimal.equal?(middle_band, Decimal.new("0")) do
        Decimal.new("0.0")
      else
        ratio = Decimal.div(band_range, middle_band)
        Decimal.mult(ratio, Decimal.new("100"))
      end

    %{
      upper_band: upper_band,
      middle_band: middle_band,
      lower_band: lower_band,
      percent_b: percent_b,
      bandwidth: bandwidth
    }
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
