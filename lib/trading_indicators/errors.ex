defmodule TradingIndicators.Errors do
  @moduledoc """
  Custom error definitions for the TradingIndicators library.

  This module defines specific exception types that provide detailed information
  about various error conditions that can occur during indicator calculations.

  ## Error Types

  - `InsufficientData` - Not enough data points for calculation
  - `InvalidParams` - Invalid parameters passed to indicator
  - `InvalidDataFormat` - Data format doesn't match expected structure
  - `CalculationError` - Error occurred during mathematical calculation
  - `StreamStateError` - Error in streaming/real-time state management

  ## Usage

  These exceptions are designed to provide clear, actionable error messages
  that help developers identify and fix issues quickly.

      try do
        SomeIndicator.calculate(data, opts)
      rescue
        exception in TradingIndicators.Errors.InsufficientData ->
          Logger.error("Need more data: \#{exception.message}")
          {:error, :insufficient_data}
      end
  """

  defmodule InsufficientData do
    @moduledoc """
    Exception for insufficient data errors.
    """

    defexception [:message, :required, :provided]

    @type t :: %__MODULE__{
            message: String.t(),
            required: non_neg_integer(),
            provided: non_neg_integer()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      required = Keyword.get(opts, :required, 0)
      provided = Keyword.get(opts, :provided, 0)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Insufficient data: required #{required}, got #{provided}"
        end)

      %__MODULE__{
        message: message,
        required: required,
        provided: provided
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, required: 0, provided: 0}
    end
  end

  defmodule InvalidParams do
    @moduledoc """
    Exception for invalid parameter errors.
    """

    defexception [:message, :param, :value, :expected]

    @type t :: %__MODULE__{
            message: String.t(),
            param: atom() | String.t(),
            value: term(),
            expected: String.t()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      param = Keyword.get(opts, :param)
      value = Keyword.get(opts, :value)
      expected = Keyword.get(opts, :expected, "valid value")

      message =
        Keyword.get_lazy(opts, :message, fn ->
          if param do
            "Invalid parameter '#{param}': got #{inspect(value)}, expected #{expected}"
          else
            "Invalid parameter value: #{inspect(value)}"
          end
        end)

      %__MODULE__{
        message: message,
        param: param,
        value: value,
        expected: expected
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, param: nil, value: nil, expected: ""}
    end
  end

  defmodule InvalidDataFormat do
    @moduledoc """
    Exception for invalid data format errors.
    """

    defexception [:message, :expected, :received, :index]

    @type t :: %__MODULE__{
            message: String.t(),
            expected: String.t(),
            received: String.t(),
            index: non_neg_integer() | nil
          }

    @impl true
    def exception(opts) when is_list(opts) do
      expected = Keyword.get(opts, :expected, "valid format")
      received = Keyword.get(opts, :received, "invalid format")
      index = Keyword.get(opts, :index)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          base_msg = "Invalid data format: expected #{expected}, got #{received}"

          if index do
            "#{base_msg} at index #{index}"
          else
            base_msg
          end
        end)

      %__MODULE__{
        message: message,
        expected: expected,
        received: received,
        index: index
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, expected: "", received: "", index: nil}
    end
  end

  defmodule CalculationError do
    @moduledoc """
    Exception for mathematical calculation errors.
    """

    defexception [:message, :operation, :values, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            operation: atom() | String.t(),
            values: [term()] | nil,
            reason: atom() | String.t()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      operation = Keyword.get(opts, :operation, :unknown)
      values = Keyword.get(opts, :values)
      reason = Keyword.get(opts, :reason, :unknown)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          base_msg = "Calculation error in operation '#{operation}'"

          if reason != :unknown do
            "#{base_msg}: #{reason}"
          else
            base_msg
          end
        end)

      %__MODULE__{
        message: message,
        operation: operation,
        values: values,
        reason: reason
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, operation: nil, values: nil, reason: nil}
    end
  end

  defmodule StreamStateError do
    @moduledoc """
    Exception for streaming state management errors.
    """

    defexception [:message, :state, :operation, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            state: term() | nil,
            operation: atom() | String.t(),
            reason: atom() | String.t()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      operation = Keyword.get(opts, :operation, :unknown)
      reason = Keyword.get(opts, :reason, :unknown)
      state = Keyword.get(opts, :state)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          base_msg = "Stream state error in operation '#{operation}'"

          if reason != :unknown do
            "#{base_msg}: #{reason}"
          else
            base_msg
          end
        end)

      %__MODULE__{
        message: message,
        state: state,
        operation: operation,
        reason: reason
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, state: nil, operation: nil, reason: nil}
    end
  end

  defmodule ValidationError do
    @moduledoc """
    Exception for data validation errors.
    """

    defexception [:message, :field, :value, :constraint]

    @type t :: %__MODULE__{
            message: String.t(),
            field: atom() | String.t(),
            value: term(),
            constraint: String.t()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      field = Keyword.get(opts, :field)
      value = Keyword.get(opts, :value)
      constraint = Keyword.get(opts, :constraint, "validation rule")

      message =
        Keyword.get_lazy(opts, :message, fn ->
          if field do
            "Validation failed for field '#{field}': #{constraint} (got #{inspect(value)})"
          else
            "Validation failed: #{constraint}"
          end
        end)

      %__MODULE__{
        message: message,
        field: field,
        value: value,
        constraint: constraint
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, field: nil, value: nil, constraint: ""}
    end
  end

  # Convenience functions for creating common errors

  @doc """
  Creates an InsufficientData exception with standardized message.

  ## Parameters

  - `indicator_name` - Name of the indicator requiring data
  - `required` - Number of data points required
  - `provided` - Number of data points provided

  ## Returns

  - InsufficientData exception struct

  ## Example

      iex> TradingIndicators.Errors.insufficient_data("SMA", 14, 10)
      %TradingIndicators.Errors.InsufficientData{
        message: "SMA requires at least 14 data points, got 10",
        required: 14,
        provided: 10
      }
  """
  @spec insufficient_data(String.t(), non_neg_integer(), non_neg_integer()) :: InsufficientData.t()
  def insufficient_data(indicator_name, required, provided) do
    %InsufficientData{
      message: "#{indicator_name} requires at least #{required} data points, got #{provided}",
      required: required,
      provided: provided
    }
  end

  @doc """
  Creates an InvalidParams exception for invalid period parameter.

  ## Parameters

  - `value` - The invalid period value provided

  ## Returns

  - InvalidParams exception struct
  """
  @spec invalid_period(term()) :: InvalidParams.t()
  def invalid_period(value) do
    %InvalidParams{
      message: "Period must be a positive integer, got #{inspect(value)}",
      param: :period,
      value: value,
      expected: "positive integer"
    }
  end

  @doc """
  Creates a ValidationError exception for negative price values.

  ## Parameters

  - `field` - The price field that was negative
  - `value` - The negative value

  ## Returns

  - ValidationError exception struct
  """
  @spec negative_price(atom(), number()) :: ValidationError.t()
  def negative_price(field, value) do
    %ValidationError{
      message: "#{String.capitalize(to_string(field))} price cannot be negative: #{value}",
      field: field,
      value: value,
      constraint: "must be non-negative"
    }
  end
end
