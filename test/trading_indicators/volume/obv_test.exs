defmodule TradingIndicators.Volume.OBVTest do
  use ExUnit.Case, async: true
  alias TradingIndicators.Volume.OBV
  require Decimal

  doctest OBV

  @test_data [
    %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
    %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]},
    %{close: Decimal.new("103"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]},
    %{close: Decimal.new("107"), volume: 1200, timestamp: ~U[2024-01-01 09:33:00Z]},
    %{close: Decimal.new("107"), volume: 900, timestamp: ~U[2024-01-01 09:34:00Z]}
  ]

  describe "calculate/2" do
    test "calculates OBV correctly for basic data series" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("103"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 3

      # First OBV = volume of first period
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))

      # Second OBV = previous OBV + volume (price went up)
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("2500.00"))

      # Third OBV = previous OBV - volume (price went down)
      assert Decimal.equal?(Enum.at(results, 2).value, Decimal.new("1700.00"))
    end

    test "handles equal price movements correctly" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100"), volume: 500, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("100"), volume: 300, timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 3
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
      # No change
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("1000.00"))
      # No change
      assert Decimal.equal?(Enum.at(results, 2).value, Decimal.new("1000.00"))
    end

    test "handles single data point" do
      data = [%{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 1
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
    end

    test "handles zero volume correctly" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("103"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 3
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
      # Zero volume added
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("1000.00"))
      # 1000 - 800
      assert Decimal.equal?(Enum.at(results, 2).value, Decimal.new("200.00"))
    end

    test "includes correct metadata" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      first = Enum.at(results, 0)
      assert first.metadata.indicator == "OBV"
      assert first.metadata.volume == 1000
      assert first.metadata.volume_direction == :initial
      assert Decimal.equal?(first.metadata.close, Decimal.new("100"))

      second = Enum.at(results, 1)
      assert second.metadata.indicator == "OBV"
      assert second.metadata.volume == 1500
      assert second.metadata.volume_direction == :positive
      assert Decimal.equal?(second.metadata.close, Decimal.new("105"))
    end

    test "returns error for insufficient data" do
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} = OBV.calculate([], [])
    end

    test "returns error for invalid parameters" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               OBV.calculate(@test_data, period: 14)
    end

    test "returns error for invalid data format" do
      invalid_data = [%{price: Decimal.new("100"), vol: 1000}]

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               OBV.calculate(invalid_data, [])
    end

    test "returns error for negative close price" do
      invalid_data = [
        %{close: Decimal.new("-100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               OBV.calculate(invalid_data, [])
    end

    test "returns error for negative volume" do
      invalid_data = [
        %{close: Decimal.new("100"), volume: -1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               OBV.calculate(invalid_data, [])
    end

    test "returns error for non-decimal close price" do
      invalid_data = [%{close: 100.0, volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               OBV.calculate(invalid_data, [])
    end
  end

  describe "validate_params/1" do
    test "accepts empty options" do
      assert :ok == OBV.validate_params([])
    end

    test "rejects non-empty options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               OBV.validate_params(period: 14)
    end

    test "rejects non-keyword list options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               OBV.validate_params("invalid")
    end
  end

  describe "required_periods/0" do
    test "returns minimum periods required" do
      assert OBV.required_periods() == 1
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes properly" do
      state = OBV.init_state([])

      assert state.obv_value == nil
      assert state.previous_close == nil
      assert state.count == 0
    end

    test "update_state/2 handles first data point" do
      state = OBV.init_state([])
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}

      {:ok, new_state, result} = OBV.update_state(state, data_point)

      assert Decimal.equal?(new_state.obv_value, Decimal.new("1000"))
      assert Decimal.equal?(new_state.previous_close, Decimal.new("100"))
      assert new_state.count == 1
      assert Decimal.equal?(result.value, Decimal.new("1000.00"))
    end

    test "update_state/2 handles subsequent data points" do
      state = %{
        obv_value: Decimal.new("1000"),
        previous_close: Decimal.new("100"),
        count: 1
      }

      # Price increase
      data_point = %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, new_state, result} = OBV.update_state(state, data_point)

      assert Decimal.equal?(new_state.obv_value, Decimal.new("2500"))
      assert Decimal.equal?(result.value, Decimal.new("2500.00"))
      assert result.metadata.volume_direction == :positive

      # Price decrease
      data_point2 = %{close: Decimal.new("103"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
      {:ok, final_state, result2} = OBV.update_state(new_state, data_point2)

      assert Decimal.equal?(final_state.obv_value, Decimal.new("1700"))
      assert Decimal.equal?(result2.value, Decimal.new("1700.00"))
      assert result2.metadata.volume_direction == :negative

      # Price unchanged
      data_point3 = %{close: Decimal.new("103"), volume: 500, timestamp: ~U[2024-01-01 09:33:00Z]}
      {:ok, unchanged_state, result3} = OBV.update_state(final_state, data_point3)

      assert Decimal.equal?(unchanged_state.obv_value, Decimal.new("1700"))
      assert Decimal.equal?(result3.value, Decimal.new("1700.00"))
      assert result3.metadata.volume_direction == :neutral
    end

    test "update_state/2 handles invalid state" do
      invalid_state = %{invalid: true}
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               OBV.update_state(invalid_state, data_point)
    end

    test "update_state/2 handles invalid data point" do
      state = OBV.init_state([])
      invalid_data = %{price: 100, vol: 1000}

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               OBV.update_state(state, invalid_data)
    end
  end

  describe "edge cases and robustness" do
    test "handles large volume numbers" do
      data = [
        %{close: Decimal.new("100"), volume: 1_000_000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), volume: 2_000_000, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 2
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000000.00"))
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("3000000.00"))
    end

    test "handles precise decimal calculations" do
      data = [
        %{close: Decimal.new("100.1234"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100.1235"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = OBV.calculate(data, [])

      assert length(results) == 2
      # Verify precision is maintained
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("2500.00"))
    end

    test "handles many periods efficiently" do
      # Generate 1000 data points
      large_data =
        1..1000
        |> Enum.map(fn i ->
          price = if rem(i, 2) == 0, do: "100", else: "101"

          %{
            close: Decimal.new(price),
            volume: 1000 + i,
            timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :second)
          }
        end)

      {:ok, results} = OBV.calculate(large_data, [])

      assert length(results) == 1000
      # Verify last result makes sense
      last_result = List.last(results)
      assert Decimal.is_decimal(last_result.value)
    end
  end

  describe "parameter_metadata/0" do
    test "returns empty list for indicators without parameters" do
      metadata = OBV.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 0
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = OBV.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = OBV.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
