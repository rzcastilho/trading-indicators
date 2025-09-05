defmodule TradingIndicators.Security do
  @moduledoc """
  Security validation and input sanitization for the TradingIndicators library.

  This module provides comprehensive security checks to ensure safe operation
  with untrusted input data and prevent various attack vectors.
  """

  @doc """
  Validates input data for security concerns including size limits,
  data type validation, and potential injection attacks.
  """
  @spec validate_input(any()) :: :ok | {:error, String.t()}
  def validate_input(data) when is_list(data) do
    with :ok <- validate_list_size(data),
         :ok <- validate_list_content(data),
         :ok <- validate_memory_safety(data) do
      :ok
    end
  end

  def validate_input(%Decimal{} = decimal) do
    cond do
      Decimal.nan?(decimal) ->
        {:error, "Decimal is NaN"}

      Decimal.inf?(decimal) ->
        {:error, "Decimal is infinite"}

      decimal_exceeds_bounds?(decimal) ->
        {:error, "Decimal exceeds safe bounds"}

      true ->
        :ok
    end
  end

  def validate_input(data) when is_map(data) do
    with :ok <- validate_map_keys(data),
         :ok <- validate_map_values(data),
         :ok <- validate_memory_safety(data) do
      :ok
    end
  end

  def validate_input(data) when is_binary(data) do
    with :ok <- validate_string_size(data),
         :ok <- validate_string_content(data) do
      :ok
    end
  end

  def validate_input(data) when is_number(data) do
    validate_number_bounds(data)
  end

  def validate_input(_data) do
    {:error, "Unsupported data type"}
  end

  @doc """
  Validates parameters for indicator calculations to prevent
  resource exhaustion attacks.
  """
  @spec validate_parameters(map()) :: :ok | {:error, String.t()}
  def validate_parameters(params) when is_map(params) do
    with :ok <- validate_period_parameter(params),
         :ok <- validate_multiplier_parameter(params),
         :ok <- validate_custom_parameters(params) do
      :ok
    end
  end

  @doc """
  Validates OHLCV data for security issues including data injection,
  timestamp manipulation, and extreme values.
  """
  @spec validate_ohlcv_security([map()]) :: :ok | {:error, String.t()}
  def validate_ohlcv_security(ohlcv_data) when is_list(ohlcv_data) do
    with :ok <- validate_ohlcv_list_size(ohlcv_data),
         :ok <- validate_ohlcv_structure(ohlcv_data),
         :ok <- validate_ohlcv_values(ohlcv_data),
         :ok <- validate_timestamp_security(ohlcv_data) do
      :ok
    end
  end

  @doc """
  Sanitizes string input to prevent injection attacks.
  """
  @spec sanitize_string(String.t()) :: String.t()
  def sanitize_string(input) when is_binary(input) do
    input
    |> String.trim()
    |> remove_dangerous_chars()
    |> limit_string_length()
  end

  @doc """
  Rate limiting check for API usage patterns.
  """
  @spec check_rate_limit(String.t()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(identifier) do
    # Simple in-memory rate limiting for demonstration
    # In production, use Redis or similar
    case :ets.whereis(:rate_limit_table) do
      :undefined ->
        :ets.new(:rate_limit_table, [:set, :public, :named_table])
        current_time = System.system_time(:second)
        :ets.insert(:rate_limit_table, {identifier, 1, current_time})
        :ok

      _ ->
        check_existing_rate_limit(identifier)
    end
  end

  # Private functions for input validation

  defp validate_list_size(list) do
    max_size = Application.get_env(:trading_indicators, :max_list_size, 100_000)

    if length(list) > max_size do
      {:error, "List size exceeds maximum allowed (#{max_size})"}
    else
      :ok
    end
  end

  defp validate_list_content(list) do
    # Check for dangerous content in list items
    dangerous_items = Enum.filter(list, &potentially_dangerous?/1)

    if Enum.empty?(dangerous_items) do
      :ok
    else
      {:error, "List contains potentially dangerous content"}
    end
  end

  defp validate_memory_safety(data) do
    data_size = :erlang.external_size(data)
    # 50MB
    max_size = Application.get_env(:trading_indicators, :max_data_size, 50_000_000)

    if data_size > max_size do
      {:error, "Data size exceeds memory safety limit"}
    else
      :ok
    end
  end

  defp validate_map_keys(map) do
    dangerous_keys =
      Map.keys(map)
      |> Enum.filter(&dangerous_key?/1)

    if Enum.empty?(dangerous_keys) do
      :ok
    else
      {:error, "Map contains dangerous keys: #{inspect(dangerous_keys)}"}
    end
  end

  defp validate_map_values(map) do
    dangerous_values =
      Map.values(map)
      |> Enum.filter(&potentially_dangerous?/1)

    if Enum.empty?(dangerous_values) do
      :ok
    else
      {:error, "Map contains dangerous values"}
    end
  end

  defp validate_string_size(string) do
    max_length = Application.get_env(:trading_indicators, :max_string_length, 1000)

    if String.length(string) > max_length do
      {:error, "String exceeds maximum length (#{max_length})"}
    else
      :ok
    end
  end

  defp validate_string_content(string) do
    dangerous_patterns = [
      # Path traversal
      ~r/\.\./,
      # Injection chars
      ~r/[<>'"]/,
      # Template injection
      ~r/\${/,
      # JavaScript protocol
      ~r/javascript:/i,
      # Data protocol
      ~r/data:/i,
      # Code evaluation
      ~r/eval\(/i,
      # Code execution
      ~r/exec\(/i,
      # Python dunder methods
      ~r/__.*__/
    ]

    if Enum.any?(dangerous_patterns, &Regex.match?(&1, string)) do
      {:error, "String contains dangerous patterns"}
    else
      :ok
    end
  end

  defp validate_number_bounds(number) do
    cond do
      not is_finite_number?(number) ->
        {:error, "Number is not finite"}

      number > 1.0e20 ->
        {:error, "Number exceeds maximum safe value"}

      number < -1.0e20 ->
        {:error, "Number below minimum safe value"}

      true ->
        :ok
    end
  end

  defp validate_decimal_safety(%Decimal{} = decimal) do
    cond do
      Decimal.nan?(decimal) ->
        {:error, "Decimal is NaN"}

      Decimal.inf?(decimal) ->
        {:error, "Decimal is infinite"}

      decimal_exceeds_bounds?(decimal) ->
        {:error, "Decimal exceeds safe bounds"}

      true ->
        :ok
    end
  end

  defp validate_period_parameter(params) do
    case Map.get(params, :period) do
      nil ->
        :ok

      period when is_integer(period) and period > 0 and period <= 1000 ->
        :ok

      period when is_integer(period) ->
        {:error, "Period #{period} outside safe range (1-1000)"}

      _ ->
        {:error, "Invalid period parameter type"}
    end
  end

  defp validate_multiplier_parameter(params) do
    multiplier_keys = [:multiplier, :std_dev, :factor]

    Enum.reduce_while(multiplier_keys, :ok, fn key, _acc ->
      case Map.get(params, key) do
        nil ->
          {:cont, :ok}

        %Decimal{} = decimal ->
          if Decimal.gt?(decimal, Decimal.new("10")) or Decimal.lt?(decimal, Decimal.new("0.1")) do
            {:halt, {:error, "#{key} outside safe range (0.1-10)"}}
          else
            {:cont, :ok}
          end

        value when is_number(value) ->
          if value > 10.0 or value < 0.1 do
            {:halt, {:error, "#{key} outside safe range (0.1-10)"}}
          else
            {:cont, :ok}
          end

        _ ->
          {:halt, {:error, "Invalid #{key} parameter type"}}
      end
    end)
  end

  defp validate_custom_parameters(params) do
    # Additional validation for custom parameters
    reserved_keys = [:__proto__, :__defineGetter__, :__defineSetter__, :__lookupGetter__]

    dangerous_keys =
      Map.keys(params)
      |> Enum.filter(fn key -> key in reserved_keys end)

    if Enum.empty?(dangerous_keys) do
      :ok
    else
      {:error, "Parameters contain reserved/dangerous keys"}
    end
  end

  defp validate_ohlcv_list_size(ohlcv_data) do
    max_size = Application.get_env(:trading_indicators, :max_ohlcv_size, 50_000)

    if length(ohlcv_data) > max_size do
      {:error, "OHLCV data exceeds maximum size (#{max_size})"}
    else
      :ok
    end
  end

  defp validate_ohlcv_structure(ohlcv_data) do
    required_keys = [:open, :high, :low, :close, :volume]

    invalid_bars =
      Enum.with_index(ohlcv_data)
      |> Enum.filter(fn {bar, _index} ->
        not is_map(bar) or not Enum.all?(required_keys, &Map.has_key?(bar, &1))
      end)

    if Enum.empty?(invalid_bars) do
      :ok
    else
      {:error, "OHLCV data contains invalid structure"}
    end
  end

  defp validate_ohlcv_values(ohlcv_data) do
    Enum.with_index(ohlcv_data)
    |> Enum.reduce_while(:ok, fn {bar, index}, _acc ->
      case validate_ohlcv_bar_values(bar) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "Bar #{index}: #{reason}"}}
      end
    end)
  end

  defp validate_ohlcv_bar_values(bar) do
    with :ok <- validate_price_values(bar),
         :ok <- validate_volume_value(bar),
         :ok <- validate_ohlc_relationships(bar) do
      :ok
    end
  end

  defp validate_price_values(bar) do
    price_keys = [:open, :high, :low, :close]

    Enum.reduce_while(price_keys, :ok, fn key, _acc ->
      price = Map.get(bar, key)

      cond do
        is_nil(price) ->
          {:halt, {:error, "Missing #{key} price"}}

        match?(%Decimal{}, price) and Decimal.gt?(price, Decimal.new("0")) and
            Decimal.lt?(price, Decimal.new("1000000")) ->
          {:cont, :ok}

        is_number(price) and price > 0 and price < 1_000_000 ->
          {:cont, :ok}

        true ->
          {:halt, {:error, "Invalid #{key} price: #{inspect(price)}"}}
      end
    end)
  end

  defp validate_volume_value(bar) do
    volume = Map.get(bar, :volume)

    cond do
      is_nil(volume) ->
        {:error, "Missing volume"}

      is_integer(volume) and volume >= 0 and volume <= 1_000_000_000 ->
        :ok

      true ->
        {:error, "Invalid volume: #{inspect(volume)}"}
    end
  end

  defp validate_ohlc_relationships(bar) do
    %{open: open, high: high, low: low, close: close} = bar

    # Convert to decimals for comparison if needed
    {open_d, high_d, low_d, close_d} = normalize_prices(open, high, low, close)

    cond do
      Decimal.lt?(high_d, open_d) or Decimal.lt?(high_d, close_d) ->
        {:error, "High price must be >= open and close"}

      Decimal.gt?(low_d, open_d) or Decimal.gt?(low_d, close_d) ->
        {:error, "Low price must be <= open and close"}

      true ->
        :ok
    end
  end

  defp validate_timestamp_security(ohlcv_data) do
    now = DateTime.utc_now()
    # 1 day in future
    future_limit = DateTime.add(now, 86400)
    # 1 year in past
    past_limit = DateTime.add(now, -31_536_000)

    invalid_timestamps =
      Enum.with_index(ohlcv_data)
      |> Enum.filter(fn {bar, _index} ->
        case Map.get(bar, :timestamp) do
          %DateTime{} = timestamp ->
            DateTime.compare(timestamp, future_limit) == :gt or
              DateTime.compare(timestamp, past_limit) == :lt

          _ ->
            # Invalid timestamp type
            true
        end
      end)

    if Enum.empty?(invalid_timestamps) do
      :ok
    else
      {:error, "OHLCV data contains invalid timestamps"}
    end
  end

  defp remove_dangerous_chars(string) do
    string
    |> String.replace(~r/[<>"'`]/, "")
    |> String.replace(~r/\$\{.*\}/, "")
    |> String.replace(~r/javascript:/i, "")
    |> String.replace(~r/data:/i, "")
  end

  defp limit_string_length(string) do
    max_length = Application.get_env(:trading_indicators, :max_sanitized_length, 100)
    String.slice(string, 0, max_length)
  end

  defp check_existing_rate_limit(identifier) do
    current_time = System.system_time(:second)

    case :ets.lookup(:rate_limit_table, identifier) do
      [{_id, count, window_start}] ->
        if current_time - window_start > 60 do
          # Reset window
          :ets.insert(:rate_limit_table, {identifier, 1, current_time})
          :ok
        else
          # 100 requests per minute
          if count >= 100 do
            {:error, :rate_limited}
          else
            :ets.insert(:rate_limit_table, {identifier, count + 1, window_start})
            :ok
          end
        end

      [] ->
        :ets.insert(:rate_limit_table, {identifier, 1, current_time})
        :ok
    end
  end

  defp potentially_dangerous?(data) do
    case data do
      binary when is_binary(binary) ->
        case validate_string_content(binary) do
          {:error, _} -> true
          :ok -> false
        end

      map when is_map(map) ->
        dangerous_key?(Map.keys(map)) or potentially_dangerous?(Map.values(map))

      list when is_list(list) ->
        Enum.any?(list, &potentially_dangerous?/1)

      %Decimal{} = decimal ->
        case validate_decimal_safety(decimal) do
          {:error, _} -> true
          :ok -> false
        end

      number when is_number(number) ->
        case validate_number_bounds(number) do
          {:error, _} -> true
          :ok -> false
        end

      _ ->
        false
    end
  end

  defp dangerous_key?(key) when is_atom(key) do
    key_string = Atom.to_string(key)
    dangerous_key?(key_string)
  end

  defp dangerous_key?(key) when is_binary(key) do
    dangerous_patterns = [
      "__proto__",
      "__defineGetter__",
      "__defineSetter__",
      "__lookupGetter__",
      "__lookupSetter__",
      "constructor",
      "prototype"
    ]

    key in dangerous_patterns or String.contains?(key, ["../", "..\\", "eval(", "exec("])
  end

  defp dangerous_key?(keys) when is_list(keys) do
    Enum.any?(keys, &dangerous_key?/1)
  end

  defp dangerous_key?(_), do: false

  defp is_finite_number?(num) when is_integer(num), do: true

  defp is_finite_number?(num) when is_float(num) do
    not (num != num or num == :infinity or num == :neg_infinity)
  end

  defp is_finite_number?(_), do: false

  defp decimal_exceeds_bounds?(%Decimal{} = decimal) do
    max_bound = Decimal.new("1E20")
    min_bound = Decimal.new("-1E20")

    Decimal.gt?(decimal, max_bound) or Decimal.lt?(decimal, min_bound)
  end

  defp normalize_prices(open, high, low, close) do
    normalize_price = fn
      %Decimal{} = d -> d
      num when is_number(num) -> Decimal.from_float(num)
    end

    {
      normalize_price.(open),
      normalize_price.(high),
      normalize_price.(low),
      normalize_price.(close)
    }
  end
end
