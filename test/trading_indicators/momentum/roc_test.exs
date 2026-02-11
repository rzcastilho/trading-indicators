defmodule TradingIndicators.Momentum.ROCTest do
  use ExUnit.Case
  alias TradingIndicators.Momentum.ROC
  require Decimal
  doctest ROC

  describe "calculate/2" do
    test "calculates ROC percentage with sufficient data" do
      data = create_test_data(15)

      {:ok, results} = ROC.calculate(data, period: 12, variant: :percentage)

      assert length(results) == 3

      result = List.first(results)
      assert %{value: roc_value, timestamp: _timestamp, metadata: metadata} = result

      assert Decimal.is_decimal(roc_value)

      assert metadata.indicator == "ROC"
      assert metadata.period == 12
      assert metadata.variant == :percentage
      assert metadata.signal in [:bullish, :bearish, :neutral]
    end

    test "calculates ROC price difference variant" do
      data = create_test_data(15)

      {:ok, results} = ROC.calculate(data, period: 10, variant: :price)

      assert length(results) >= 1

      result = List.first(results)
      assert result.metadata.variant == :price
      assert Decimal.is_decimal(result.value)
    end

    test "works with price series input" do
      prices = [
        Decimal.new("100"),
        Decimal.new("102"),
        Decimal.new("101"),
        Decimal.new("103"),
        Decimal.new("105"),
        Decimal.new("104"),
        Decimal.new("106"),
        Decimal.new("108"),
        Decimal.new("107"),
        Decimal.new("109"),
        Decimal.new("111"),
        Decimal.new("110"),
        Decimal.new("112"),
        Decimal.new("114"),
        Decimal.new("113")
      ]

      {:ok, results} = ROC.calculate(prices, period: 12)

      assert length(results) >= 1
      assert Decimal.is_decimal(List.first(results).value)
    end

    test "returns error for insufficient data" do
      data = create_test_data(5)

      {:error, error} = ROC.calculate(data, period: 12)

      assert %TradingIndicators.Errors.InsufficientData{} = error
      assert error.required == 13
      assert error.provided == 5
    end

    test "validates parameters correctly" do
      data = create_test_data(20)

      # Invalid period
      {:error, error} = ROC.calculate(data, period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :period

      # Invalid source
      {:error, error} = ROC.calculate(data, source: :invalid)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :source

      # Invalid variant
      {:error, error} = ROC.calculate(data, variant: :invalid)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :variant
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes proper state" do
      state = ROC.init_state(period: 12, source: :close, variant: :percentage)

      assert state.roc_period == 12
      assert state.source == :close
      assert state.variant == :percentage
      assert state.historical_prices == []
      assert state.count == 0
    end

    test "update_state/2 processes data points correctly" do
      state = ROC.init_state(period: 3)

      data_points = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
        %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:34:00Z]}
      ]

      {final_state, final_result} =
        Enum.reduce(data_points, {state, nil}, fn data_point, {acc_state, _} ->
          {:ok, new_state, result} = ROC.update_state(acc_state, data_point)
          {new_state, result}
        end)

      assert final_state.count == 5
      # Should have a result after period + 1 data points
      assert is_map(final_result)
      assert final_result.metadata.indicator == "ROC"
      assert Decimal.is_decimal(final_result.value)
    end

    test "update_state/2 works with price series" do
      state = ROC.init_state(period: 2)

      prices = [
        Decimal.new("100"),
        Decimal.new("102"),
        Decimal.new("104")
      ]

      {_final_state, final_result} =
        Enum.reduce(prices, {state, nil}, fn price, {acc_state, _} ->
          {:ok, new_state, result} = ROC.update_state(acc_state, price)
          {new_state, result}
        end)

      assert is_map(final_result)
      assert Decimal.is_decimal(final_result.value)
    end
  end

  describe "mathematical accuracy" do
    test "calculates correct percentage ROC" do
      # Simple test case: price goes from 100 to 110, ROC = 10%
      data_points = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = ROC.calculate(data_points, period: 2, variant: :percentage)

      assert length(results) == 1
      result = List.first(results)

      # ROC% = ((110 - 100) / 100) * 100 = 10%
      expected_roc = Decimal.new("10.00")
      assert Decimal.equal?(result.value, expected_roc)
    end

    test "calculates correct price ROC" do
      # Simple test case: price goes from 100 to 110, price difference = 10
      data_points = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = ROC.calculate(data_points, period: 2, variant: :price)

      assert length(results) == 1
      result = List.first(results)

      # Price ROC = 110 - 100 = 10
      expected_roc = Decimal.new("10.00")
      assert Decimal.equal?(result.value, expected_roc)
    end

    test "handles zero division correctly" do
      # Test case with zero historical price
      data_points = [
        %{close: Decimal.new("0"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = ROC.calculate(data_points, period: 1, variant: :percentage)

      assert length(results) == 1
      result = List.first(results)

      # Should return 0 to avoid division by zero
      expected_roc = Decimal.new("0")
      assert Decimal.equal?(result.value, expected_roc)
    end
  end

  describe "required_periods/0" do
    test "returns default required periods" do
      # default period (12) + 1
      assert ROC.required_periods() == 13
    end
  end

  describe "required_periods/1" do
    test "returns configured required periods" do
      assert ROC.required_periods(period: 10) == 11
    end
  end

  # Helper function to create test data
  defp create_test_data(count) do
    base_price = 100

    1..count
    |> Enum.map(fn i ->
      price = base_price + :rand.uniform(20) - 10

      %{
        close: Decimal.new(price),
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
      }
    end)
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = ROC.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = ROC.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
