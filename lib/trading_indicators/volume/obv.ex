defmodule TradingIndicators.Volume.OBV do
  @moduledoc """
  On-Balance Volume (OBV) indicator implementation.

  On-Balance Volume (OBV) is a momentum indicator that uses volume flow to predict 
  changes in stock price. It was developed by Joe Granville and introduced in his 
  1963 book "Granville's New Key to Stock Market Profits."

  ## Formula

  - If Close > Previous Close: OBV = Previous OBV + Volume
  - If Close < Previous Close: OBV = Previous OBV - Volume  
  - If Close = Previous Close: OBV = Previous OBV

  ## Theory

  OBV is based on the premise that volume precedes price movement. If a stock closes
  higher on increased volume, institutional money is flowing into the stock. If it
  closes lower on increased volume, money is flowing out. The running total provides
  a cumulative measure of money flow.

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("103"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volume.OBV.calculate(data, [])
      iex> Enum.map(result, &Decimal.to_integer(&1.value))
      [1000, 2500, 1700]

  ## Usage Notes

  - Returns results for all data points (first point starts the cumulative total)
  - Requires close prices and volume data
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Volume must be non-negative integers
  - Close prices must be valid Decimal values

  ## Interpretation

  - **Rising OBV** - Suggests accumulation and potential upward price movement
  - **Falling OBV** - Suggests distribution and potential downward price movement
  - **Divergence** - OBV moving opposite to price can signal trend reversal
  - **Breakouts** - OBV breaking to new highs/lows can confirm price breakouts
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @precision 2

  @doc """
  Calculates On-Balance Volume for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires close and volume)
  - `opts` - Calculation options (keyword list) - currently no options supported

  ## Returns

  - `{:ok, results}` - List of OBV calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = OBV.calculate(data, [])
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         :ok <- Utils.validate_data_length(data, 1),
         :ok <- validate_ohlcv_data(data) do
      calculate_obv_values(data)
    end
  end

  @doc """
  Validates parameters for OBV calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    # OBV currently doesn't accept any parameters
    if Enum.empty?(opts) do
      :ok
    else
      # Check for unsupported parameters
      unsupported_keys = Keyword.keys(opts)

      {:error,
       %Errors.InvalidParams{
         message: "OBV does not accept parameters. Unsupported keys: #{inspect(unsupported_keys)}",
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
  Returns the minimum number of periods required for OBV calculation.

  ## Returns

  - Always 1 (OBV can be calculated from the first data point)

  ## Example

      iex> TradingIndicators.Volume.OBV.required_periods()
      1
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: 1

  @doc """
  Initializes streaming state for real-time OBV calculation.

  ## Parameters

  - `opts` - Configuration options (currently unused)

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = OBV.init_state([])
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    # Suppress unused warning
    _ = opts

    %{
      obv_value: nil,
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

  - `{:ok, new_state, obv_result}` - Updated state with result
  - `{:error, reason}` - Error occurred

  ## Example

      state = OBV.init_state([])
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = OBV.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{obv_value: obv_value, previous_close: previous_close, count: count} = _state,
        %{close: close, volume: volume} = data_point
      ) do
    try do
      # Validate the data point
      with :ok <- validate_single_ohlcv_data(data_point) do
        new_count = count + 1

        # Calculate new OBV value
        new_obv_value =
          if previous_close do
            calculate_single_obv_step(obv_value, close, previous_close, volume)
          else
            # First data point: OBV starts with volume
            Decimal.new(volume)
          end

        new_state = %{
          obv_value: new_obv_value,
          previous_close: close,
          count: new_count
        }

        result = %{
          value: Decimal.round(new_obv_value, @precision),
          timestamp: get_timestamp(data_point),
          metadata: %{
            indicator: "OBV",
            volume: volume,
            close: close,
            volume_direction: get_volume_direction(close, previous_close)
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
       message: "Invalid state format for OBV streaming or data point missing close/volume fields",
       operation: :update_state,
       reason: "malformed state or invalid data point"
     }}
  end

  # Private functions

  defp validate_ohlcv_data([]), do: :ok

  defp validate_ohlcv_data([%{close: close, volume: volume} = data_point | rest]) do
    with :ok <- validate_close_price(close, data_point),
         :ok <- validate_volume(volume, data_point) do
      validate_ohlcv_data(rest)
    end
  end

  defp validate_ohlcv_data([invalid | _rest]) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "OBV requires data with close and volume fields",
       expected: "map with :close and :volume keys",
       received: inspect(invalid)
     }}
  end

  defp validate_single_ohlcv_data(%{close: close, volume: volume} = data_point) do
    with :ok <- validate_close_price(close, data_point),
         :ok <- validate_volume(volume, data_point) do
      :ok
    end
  end

  defp validate_single_ohlcv_data(invalid) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "OBV requires data with close and volume fields",
       expected: "map with :close and :volume keys",
       received: inspect(invalid)
     }}
  end

  defp validate_close_price(close, _data_point) when is_struct(close, Decimal) do
    if Decimal.negative?(close) do
      {:error, Errors.negative_price(:close, close)}
    else
      :ok
    end
  end

  defp validate_close_price(close, data_point) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "Close price must be a Decimal",
       expected: "Decimal.t()",
       received: "#{inspect(close)} in #{inspect(data_point)}"
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

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_obv_values([]), do: {:ok, []}

  defp calculate_obv_values([first_data | rest_data]) do
    # First OBV value is simply the first volume
    first_obv = Decimal.new(first_data.volume)

    first_result = %{
      value: Decimal.round(first_obv, @precision),
      timestamp: get_timestamp(first_data),
      metadata: %{
        indicator: "OBV",
        volume: first_data.volume,
        close: first_data.close,
        volume_direction: :initial
      }
    }

    # Process remaining data points
    {final_results, _final_obv} =
      rest_data
      |> Enum.reduce({[first_result], first_obv}, fn current_data, {acc_results, prev_obv} ->
        # Get previous close from last processed data point
        prev_close = get_previous_close(acc_results)

        # Calculate new OBV value
        new_obv =
          calculate_single_obv_step(prev_obv, current_data.close, prev_close, current_data.volume)

        result = %{
          value: Decimal.round(new_obv, @precision),
          timestamp: get_timestamp(current_data),
          metadata: %{
            indicator: "OBV",
            volume: current_data.volume,
            close: current_data.close,
            volume_direction: get_volume_direction(current_data.close, prev_close)
          }
        }

        {[result | acc_results], new_obv}
      end)

    {:ok, Enum.reverse(final_results)}
  end

  defp get_previous_close([%{metadata: %{close: close}} | _]), do: close
  defp get_previous_close([]), do: nil

  defp calculate_single_obv_step(prev_obv, current_close, prev_close, volume) do
    volume_decimal = Decimal.new(volume)

    cond do
      Decimal.gt?(current_close, prev_close) ->
        # Price up: add volume
        Decimal.add(prev_obv, volume_decimal)

      Decimal.lt?(current_close, prev_close) ->
        # Price down: subtract volume
        Decimal.sub(prev_obv, volume_decimal)

      true ->
        # Price unchanged: OBV unchanged
        prev_obv
    end
  end

  defp get_volume_direction(_current_close, nil), do: :initial

  defp get_volume_direction(current_close, prev_close) do
    cond do
      Decimal.gt?(current_close, prev_close) -> :positive
      Decimal.lt?(current_close, prev_close) -> :negative
      true -> :neutral
    end
  end
end
