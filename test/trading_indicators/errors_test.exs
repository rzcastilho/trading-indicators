defmodule TradingIndicators.ErrorsTest do
  use ExUnit.Case, async: true
  require Decimal

  alias TradingIndicators.Errors

  describe "InsufficientData exception" do
    test "creates exception with keyword list" do
      error = Errors.InsufficientData.exception(required: 10, provided: 5)

      assert error.required == 10
      assert error.provided == 5
      assert error.message == "Insufficient data: required 10, got 5"
    end

    test "creates exception with custom message" do
      error =
        Errors.InsufficientData.exception(
          message: "Custom error message",
          required: 20,
          provided: 15
        )

      assert error.message == "Custom error message"
      assert error.required == 20
      assert error.provided == 15
    end

    test "creates exception with string message" do
      error = Errors.InsufficientData.exception("Simple message")

      assert error.message == "Simple message"
      assert error.required == 0
      assert error.provided == 0
    end
  end

  describe "InvalidParams exception" do
    test "creates exception with keyword list" do
      error =
        Errors.InvalidParams.exception(
          param: :period,
          value: -5,
          expected: "positive integer"
        )

      assert error.param == :period
      assert error.value == -5
      assert error.expected == "positive integer"
      assert String.contains?(error.message, "period")
      assert String.contains?(error.message, "-5")
    end

    test "creates exception without param name" do
      error = Errors.InvalidParams.exception(value: "invalid", expected: "number")

      assert error.param == nil
      assert String.contains?(error.message, "Invalid parameter value")
    end

    test "creates exception with string message" do
      error = Errors.InvalidParams.exception("Simple error")

      assert error.message == "Simple error"
      assert error.param == nil
      assert error.value == nil
    end
  end

  describe "InvalidDataFormat exception" do
    test "creates exception with keyword list" do
      error =
        Errors.InvalidDataFormat.exception(
          expected: "OHLCV map",
          received: "string",
          index: 5
        )

      assert error.expected == "OHLCV map"
      assert error.received == "string"
      assert error.index == 5
      assert String.contains?(error.message, "at index 5")
    end

    test "creates exception without index" do
      error =
        Errors.InvalidDataFormat.exception(
          expected: "map",
          received: "list"
        )

      assert error.index == nil
      refute String.contains?(error.message, "at index")
    end
  end

  describe "CalculationError exception" do
    test "creates exception with keyword list" do
      error =
        Errors.CalculationError.exception(
          operation: :divide,
          values: [Decimal.new("10.0"), Decimal.new("0.0")],
          reason: :division_by_zero
        )

      assert error.operation == :divide
      assert error.values == [Decimal.new("10.0"), Decimal.new("0.0")]
      assert error.reason == :division_by_zero
      assert String.contains?(error.message, "divide")
      assert String.contains?(error.message, "division_by_zero")
    end

    test "creates exception with minimal information" do
      error = Errors.CalculationError.exception(operation: :sqrt)

      assert error.operation == :sqrt
      assert error.reason == :unknown
    end
  end

  describe "StreamStateError exception" do
    test "creates exception with keyword list" do
      error =
        Errors.StreamStateError.exception(
          operation: :update_state,
          reason: :invalid_data,
          state: %{count: 5}
        )

      assert error.operation == :update_state
      assert error.reason == :invalid_data
      assert error.state == %{count: 5}
      assert String.contains?(error.message, "update_state")
    end
  end

  describe "ValidationError exception" do
    test "creates exception with field information" do
      error =
        Errors.ValidationError.exception(
          field: :close,
          value: Decimal.new("-10.5"),
          constraint: "must be positive"
        )

      assert error.field == :close
      assert Decimal.equal?(error.value, Decimal.new("-10.5"))
      assert error.constraint == "must be positive"
      assert String.contains?(error.message, "close")
      assert String.contains?(error.message, "-10.5")
    end

    test "creates exception without field" do
      error = Errors.ValidationError.exception(constraint: "general validation rule")

      assert error.field == nil
      assert String.contains?(error.message, "general validation rule")
    end
  end

  describe "convenience functions" do
    test "insufficient_data/3 creates standardized error" do
      error = Errors.insufficient_data("SMA", 14, 10)

      assert %Errors.InsufficientData{} = error
      assert error.required == 14
      assert error.provided == 10
      assert String.contains?(error.message, "SMA")
      assert String.contains?(error.message, "14")
      assert String.contains?(error.message, "10")
    end

    test "invalid_period/1 creates period validation error" do
      error = Errors.invalid_period(-5)

      assert %Errors.InvalidParams{} = error
      assert error.param == :period
      assert error.value == -5
      assert error.expected == "positive integer"
      assert String.contains?(error.message, "positive integer")
    end

    test "negative_price/2 creates price validation error" do
      error = Errors.negative_price(:close, Decimal.new("-10.5"))

      assert %Errors.ValidationError{} = error
      assert error.field == :close
      assert Decimal.equal?(error.value, Decimal.new("-10.5"))
      assert error.constraint == "must be non-negative"
      assert String.contains?(error.message, "Close")
      assert String.contains?(error.message, "-10.5")
    end
  end

  describe "error raising and rescue" do
    test "can raise and rescue InsufficientData" do
      assert_raise Errors.InsufficientData, fn ->
        raise Errors.insufficient_data("Test", 10, 5)
      end
    end

    test "can pattern match on specific error types" do
      try do
        raise Errors.invalid_period("not_a_number")
      rescue
        e in Errors.InvalidParams ->
          assert e.param == :period
          assert e.value == "not_a_number"
      end
    end

    test "exception messages are informative" do
      errors = [
        Errors.insufficient_data("RSI", 14, 10),
        Errors.invalid_period(-1),
        Errors.negative_price(:high, Decimal.new("-100.0"))
      ]

      Enum.each(errors, fn error ->
        assert String.length(error.message) > 10
        refute String.contains?(error.message, "nil")
        refute String.contains?(error.message, "undefined")
      end)
    end
  end

  describe "error type checking" do
    test "all custom errors are proper exception structs" do
      errors = [
        Errors.InsufficientData.exception("test"),
        Errors.InvalidParams.exception("test"),
        Errors.InvalidDataFormat.exception("test"),
        Errors.CalculationError.exception("test"),
        Errors.StreamStateError.exception("test"),
        Errors.ValidationError.exception("test")
      ]

      Enum.each(errors, fn error ->
        assert is_struct(error)
        assert is_binary(error.message)
        assert String.length(error.message) > 0
      end)
    end
  end
end
