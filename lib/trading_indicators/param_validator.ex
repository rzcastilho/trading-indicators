defmodule TradingIndicators.ParamValidator do
  @moduledoc """
  Parameter validation utilities using parameter metadata.

  This module provides functions to validate indicator parameters against their
  metadata definitions, enabling automatic validation without duplicating validation
  logic across indicators.

  ## Features

  - **Type Validation**: Ensures parameter values match declared types
  - **Range Validation**: Validates numeric parameters against min/max constraints
  - **Option Validation**: Validates enum-like parameters against allowed options
  - **Required Field Validation**: Ensures required parameters are present
  - **Comprehensive Errors**: Provides detailed error messages for validation failures

  ## Examples

      # Define parameter metadata
      metadata = [
        %TradingIndicators.Types.ParamMetadata{
          name: :period,
          type: :integer,
          default: 20,
          required: false,
          min: 1,
          max: nil,
          options: nil,
          description: "Number of periods"
        },
        %TradingIndicators.Types.ParamMetadata{
          name: :source,
          type: :atom,
          default: :close,
          required: false,
          min: nil,
          max: nil,
          options: [:open, :high, :low, :close],
          description: "Source price field"
        }
      ]

      # Valid parameters
      params = [period: 14, source: :close]
      :ok = TradingIndicators.ParamValidator.validate_params(params, metadata)

      # Invalid type
      params = [period: "14", source: :close]
      {:error, %TradingIndicators.Errors.InvalidParams{}} =
        TradingIndicators.ParamValidator.validate_params(params, metadata)

      # Value out of range
      params = [period: 0, source: :close]
      {:error, %TradingIndicators.Errors.InvalidParams{}} =
        TradingIndicators.ParamValidator.validate_params(params, metadata)

      # Invalid option
      params = [period: 14, source: :invalid]
      {:error, %TradingIndicators.Errors.InvalidParams{}} =
        TradingIndicators.ParamValidator.validate_params(params, metadata)
  """

  alias TradingIndicators.{Types, Errors}
  require Decimal

  @doc """
  Validates parameters against parameter metadata definitions.

  ## Parameters

  - `params` - Keyword list of parameter values to validate
  - `metadata` - List of parameter metadata (from `parameter_metadata/0`)

  ## Returns

  - `:ok` if all parameters are valid
  - `{:error, %InvalidParams{}}` if validation fails

  ## Examples

      metadata = SMA.parameter_metadata()
      :ok = validate_params([period: 20], metadata)
      {:error, _} = validate_params([period: -5], metadata)
  """
  @spec validate_params(keyword(), [Types.param_metadata()]) ::
          :ok | {:error, Errors.InvalidParams.t()}
  def validate_params(params, metadata) when is_list(params) and is_list(metadata) do
    # Validate each parameter in params
    Enum.reduce_while(params, :ok, fn {key, value}, _acc ->
      case find_metadata(key, metadata) do
        nil ->
          # Parameter not in metadata - could be allowed or rejected
          # For now, we'll skip unknown parameters (permissive approach)
          {:cont, :ok}

        param_meta ->
          case validate_parameter(key, value, param_meta) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end
      end
    end)
    |> case do
      :ok ->
        # Check for missing required parameters
        validate_required_params(params, metadata)

      error ->
        error
    end
  end

  def validate_params(_params, _metadata) do
    {:error,
     %Errors.InvalidParams{
       message: "Parameters must be a keyword list",
       param: nil,
       value: nil,
       expected: "keyword list"
     }}
  end

  # Private Functions

  @spec find_metadata(atom(), [Types.param_metadata()]) :: Types.param_metadata() | nil
  defp find_metadata(key, metadata) do
    Enum.find(metadata, fn meta -> meta.name == key end)
  end

  @spec validate_parameter(atom(), term(), Types.param_metadata()) ::
          :ok | {:error, Errors.InvalidParams.t()}
  defp validate_parameter(key, value, meta) do
    with :ok <- validate_type(key, value, meta.type),
         :ok <- validate_range(key, value, meta.min, meta.max, meta.type),
         :ok <- validate_options(key, value, meta.options) do
      :ok
    end
  end

  @spec validate_type(atom(), term(), atom()) :: :ok | {:error, Errors.InvalidParams.t()}
  defp validate_type(key, value, :integer) do
    if is_integer(value) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         param: key,
         value: value,
         expected: "integer",
         message: "Parameter '#{key}' must be an integer, got #{inspect(value)}"
       }}
    end
  end

  defp validate_type(key, value, :float) do
    if is_float(value) or is_integer(value) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         param: key,
         value: value,
         expected: "float or number",
         message: "Parameter '#{key}' must be a float or number, got #{inspect(value)}"
       }}
    end
  end

  defp validate_type(key, value, :string) do
    if is_binary(value) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         param: key,
         value: value,
         expected: "string",
         message: "Parameter '#{key}' must be a string, got #{inspect(value)}"
       }}
    end
  end

  defp validate_type(key, value, :atom) do
    if is_atom(value) do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         param: key,
         value: value,
         expected: "atom",
         message: "Parameter '#{key}' must be an atom, got #{inspect(value)}"
       }}
    end
  end

  @spec validate_range(atom(), term(), number() | nil, number() | nil, atom()) ::
          :ok | {:error, Errors.InvalidParams.t()}
  defp validate_range(_key, _value, nil, nil, _type), do: :ok

  defp validate_range(key, value, min, max, type) when type in [:integer, :float] do
    cond do
      min != nil and value < min ->
        {:error,
         %Errors.InvalidParams{
           param: key,
           value: value,
           expected: "value >= #{min}",
           message: "Parameter '#{key}' must be >= #{min}, got #{value}"
         }}

      max != nil and value > max ->
        {:error,
         %Errors.InvalidParams{
           param: key,
           value: value,
           expected: "value <= #{max}",
           message: "Parameter '#{key}' must be <= #{max}, got #{value}"
         }}

      true ->
        :ok
    end
  end

  defp validate_range(_key, _value, _min, _max, _type), do: :ok

  @spec validate_options(atom(), term(), list() | nil) ::
          :ok | {:error, Errors.InvalidParams.t()}
  defp validate_options(_key, _value, nil), do: :ok

  defp validate_options(key, value, options) when is_list(options) do
    if value in options do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         param: key,
         value: value,
         expected: "one of #{inspect(options)}",
         message: "Parameter '#{key}' must be one of #{inspect(options)}, got #{inspect(value)}"
       }}
    end
  end

  @spec validate_required_params(keyword(), [Types.param_metadata()]) ::
          :ok | {:error, Errors.InvalidParams.t()}
  defp validate_required_params(params, metadata) do
    required_params = Enum.filter(metadata, & &1.required)

    Enum.reduce_while(required_params, :ok, fn meta, _acc ->
      if Keyword.has_key?(params, meta.name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          %Errors.InvalidParams{
            param: meta.name,
            value: nil,
            expected: "required parameter",
            message: "Required parameter '#{meta.name}' is missing"
          }}}
      end
    end)
  end
end
