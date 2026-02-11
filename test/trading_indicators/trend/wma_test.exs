defmodule TradingIndicators.Trend.WMATest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.WMA

  alias TradingIndicators.Trend.WMA
  alias TradingIndicators.Errors
  require Decimal

  describe "calculate/2" do
    setup do
      data = [
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("105.0"),
          low: Decimal.new("98.0"),
          close: Decimal.new("103.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          open: Decimal.new("103.0"),
          high: Decimal.new("107.0"),
          low: Decimal.new("101.0"),
          close: Decimal.new("105.0"),
          volume: 1200,
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          open: Decimal.new("105.0"),
          high: Decimal.new("108.0"),
          low: Decimal.new("103.0"),
          close: Decimal.new("107.0"),
          volume: 1100,
          timestamp: ~U[2024-01-01 09:32:00Z]
        },
        %{
          open: Decimal.new("107.0"),
          high: Decimal.new("109.0"),
          low: Decimal.new("105.0"),
          close: Decimal.new("106.0"),
          volume: 950,
          timestamp: ~U[2024-01-01 09:33:00Z]
        },
        %{
          open: Decimal.new("106.0"),
          high: Decimal.new("110.0"),
          low: Decimal.new("104.0"),
          close: Decimal.new("108.0"),
          volume: 1300,
          timestamp: ~U[2024-01-01 09:34:00Z]
        }
      ]

      {:ok, data: data}
    end

    test "calculates WMA correctly with simple example" do
      # Test with known values to verify calculation
      data = [
        %{close: Decimal.new("10"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("20"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("30"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      assert {:ok, results} = WMA.calculate(data, period: 3)
      assert length(results) == 1

      first_result = List.first(results)

      # WMA = (10×1 + 20×2 + 30×3) / (1+2+3) = (10 + 40 + 90) / 6 = 140/6 = 23.333333
      expected = Decimal.new("23.333333")
      assert Decimal.equal?(Decimal.round(first_result.value, 6), expected)
      assert first_result.metadata.indicator == "WMA"
      assert first_result.metadata.period == 3
    end

    test "calculates WMA with default period", %{data: data} do
      # Use shorter data for testing with smaller period
      assert {:ok, results} = WMA.calculate(data, period: 3)

      assert length(results) == 3

      [first, second, third] = results

      # Verify all are decimals and have proper metadata
      assert Decimal.is_decimal(first.value)
      assert Decimal.is_decimal(second.value)
      assert Decimal.is_decimal(third.value)

      # 3rd data point
      assert first.timestamp == ~U[2024-01-01 09:32:00Z]
      assert first.metadata.indicator == "WMA"
      assert first.metadata.period == 3
    end

    test "calculates WMA with custom period", %{data: data} do
      assert {:ok, results} = WMA.calculate(data, period: 2)

      assert length(results) == 4

      [first, second, third, fourth] = results

      # All should be valid decimals
      assert Decimal.is_decimal(first.value)
      assert Decimal.is_decimal(second.value)
      assert Decimal.is_decimal(third.value)
      assert Decimal.is_decimal(fourth.value)

      # First WMA should be at index 1 (2nd data point)
      assert first.timestamp == ~U[2024-01-01 09:31:00Z]
    end

    test "works with different price sources", %{data: data} do
      assert {:ok, high_results} = WMA.calculate(data, period: 2, source: :high)
      assert {:ok, low_results} = WMA.calculate(data, period: 2, source: :low)
      assert {:ok, open_results} = WMA.calculate(data, period: 2, source: :open)
      assert {:ok, volume_results} = WMA.calculate(data, period: 2, source: :volume)

      assert length(high_results) == 4
      assert length(low_results) == 4
      assert length(open_results) == 4
      assert length(volume_results) == 4

      # Different sources should produce different results
      first_high = List.first(high_results)
      first_low = List.first(low_results)

      refute Decimal.equal?(first_high.value, first_low.value)
      # Verify volume source produces valid results
      assert Decimal.gt?(List.first(volume_results).value, Decimal.new("0"))
    end

    test "handles price series input", %{data: data} do
      closes = Enum.map(data, & &1.close)
      assert {:ok, results} = WMA.calculate(closes, period: 2)

      assert length(results) == 4
      # When using price series, timestamps default to current time
      assert is_struct(List.first(results).timestamp, DateTime)
    end

    test "returns error for insufficient data", %{data: data} do
      short_data = Enum.take(data, 2)
      assert {:error, %Errors.InsufficientData{} = error} = WMA.calculate(short_data, period: 5)

      assert error.required == 5
      assert error.provided == 2
    end

    test "returns error for empty data" do
      assert {:error, %Errors.InsufficientData{}} = WMA.calculate([], period: 1)
    end

    test "returns error for invalid period" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = WMA.calculate(data, period: 0)
      assert {:error, %Errors.InvalidParams{}} = WMA.calculate(data, period: -1)
      assert {:error, %Errors.InvalidParams{}} = WMA.calculate(data, period: "invalid")
    end

    test "returns error for invalid source" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = WMA.calculate(data, source: :invalid)
    end

    test "WMA gives more weight to recent prices" do
      # Test that WMA is closer to recent prices than older ones
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:31:00Z]},
        # Jump up
        %{close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, wma_results} = WMA.calculate(data, period: 3)
      {:ok, sma_results} = TradingIndicators.Trend.SMA.calculate(data, period: 3)

      wma_value = List.first(wma_results).value
      sma_value = List.first(sma_results).value

      # WMA should be higher than SMA because it gives more weight to the recent higher price
      assert Decimal.gt?(wma_value, sma_value)
    end

    test "maintains precision in calculations" do
      # Create data that would cause floating point precision issues
      data = [
        %{close: Decimal.new("0.1"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.2"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("0.3"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      assert {:ok, results} = WMA.calculate(data, period: 3)

      # Should be exactly calculated, not a floating point approximation
      assert Decimal.is_decimal(List.first(results).value)
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == WMA.validate_params(period: 14, source: :close)
      assert :ok == WMA.validate_params(period: 1, source: :high)
      assert :ok == WMA.validate_params([])
    end

    test "rejects invalid period" do
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(period: 0)
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(period: -5)
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(period: "10")
    end

    test "rejects invalid source" do
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(source: :invalid)
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(source: "close")
    end

    test "rejects non-keyword list" do
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params("invalid")
      assert {:error, %Errors.InvalidParams{}} = WMA.validate_params(%{period: 10})
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default period" do
      assert WMA.required_periods() == 20
    end

    test "returns configured period" do
      assert WMA.required_periods(period: 14) == 14
      assert WMA.required_periods(period: 50) == 50
    end

    test "returns default for empty options" do
      assert WMA.required_periods([]) == 20
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = WMA.init_state(period: 10, source: :high)

      assert state.period == 10
      assert state.source == :high
      assert state.prices == []
      assert state.count == 0
      assert Decimal.is_decimal(state.weight_sum)

      # Weight sum for period 10 should be 10×11/2 = 55
      expected_weight_sum = Decimal.new("55")
      assert Decimal.equal?(state.weight_sum, expected_weight_sum)
    end

    test "init_state/1 uses defaults" do
      state = WMA.init_state()

      assert state.period == 20
      assert state.source == :close
    end

    test "update_state/2 accumulates data until period is reached" do
      state = WMA.init_state(period: 3, source: :close)

      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, state1, result1} = WMA.update_state(state, data_point1)

      # Insufficient data
      assert result1 == nil
      assert state1.count == 1
      assert length(state1.prices) == 1

      data_point2 = %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, state2, result2} = WMA.update_state(state1, data_point2)

      # Still insufficient data
      assert result2 == nil
      assert state2.count == 2
      assert length(state2.prices) == 2

      data_point3 = %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      {:ok, state3, result3} = WMA.update_state(state2, data_point3)

      # Now we have enough data
      assert result3 != nil
      assert state3.count == 3
      assert length(state3.prices) == 3
      assert Decimal.is_decimal(result3.value)
    end

    test "update_state/2 maintains rolling window" do
      state = WMA.init_state(period: 2, source: :close)

      # Add first two points
      {:ok, state, _} =
        WMA.update_state(state, %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]})

      {:ok, state, result} =
        WMA.update_state(state, %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]})

      # WMA for [100, 102] with weights [1, 2]: (100×1 + 102×2) / (1+2) = 304/3 = 101.333333
      expected = Decimal.new("101.333333")
      assert Decimal.equal?(Decimal.round(result.value, 6), expected)

      # Add third point - should maintain window size of 2
      {:ok, state, result} =
        WMA.update_state(state, %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]})

      # Window size maintained
      assert length(state.prices) == 2
      # WMA for [102, 104] with weights [1, 2]: (102×1 + 104×2) / (1+2) = 310/3 = 103.333333
      expected = Decimal.new("103.333333")
      assert Decimal.equal?(Decimal.round(result.value, 6), expected)
    end

    test "update_state/2 handles different sources" do
      state = WMA.init_state(period: 2, source: :high)

      data_point1 = %{high: Decimal.new("105"), timestamp: ~U[2024-01-01 09:30:00Z]}
      data_point2 = %{high: Decimal.new("107"), timestamp: ~U[2024-01-01 09:31:00Z]}

      {:ok, state, _} = WMA.update_state(state, data_point1)
      {:ok, _state, result} = WMA.update_state(state, data_point2)

      # WMA for [105, 107] with weights [1, 2]: (105×1 + 107×2) / (1+2) = 319/3 = 106.333333
      expected = Decimal.new("106.333333")
      assert Decimal.equal?(Decimal.round(result.value, 6), expected)
      assert result.metadata.source == :high
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}

      assert {:error, %Errors.StreamStateError{}} = WMA.update_state(invalid_state, data_point)
    end
  end

  describe "mathematical accuracy" do
    test "weight calculation is correct" do
      # Test weight sum calculation for various periods
      state3 = WMA.init_state(period: 3)
      # 1+2+3 = 6
      expected3 = Decimal.new("6")
      assert Decimal.equal?(state3.weight_sum, expected3)

      state5 = WMA.init_state(period: 5)
      # 1+2+3+4+5 = 15
      expected5 = Decimal.new("15")
      assert Decimal.equal?(state5.weight_sum, expected5)
    end

    test "WMA calculation follows formula exactly" do
      # Manual calculation test
      data = [
        %{close: Decimal.new("10"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("20"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("30"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("40"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ]

      {:ok, results} = WMA.calculate(data, period: 2)

      # First WMA: [10, 20] with weights [1, 2]: (10×1 + 20×2) / 3 = 50/3 = 16.666667
      assert Decimal.equal?(Decimal.round(Enum.at(results, 0).value, 6), Decimal.new("16.666667"))

      # Second WMA: [20, 30] with weights [1, 2]: (20×1 + 30×2) / 3 = 80/3 = 26.666667
      assert Decimal.equal?(Decimal.round(Enum.at(results, 1).value, 6), Decimal.new("26.666667"))

      # Third WMA: [30, 40] with weights [1, 2]: (30×1 + 40×2) / 3 = 110/3 = 36.666667
      assert Decimal.equal?(Decimal.round(Enum.at(results, 2).value, 6), Decimal.new("36.666667"))
    end

    test "handles very large numbers" do
      data = [
        %{close: Decimal.new("999999999.99"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("1000000000.01"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:ok, results} = WMA.calculate(data, period: 2)
      result_value = List.first(results).value

      # Should handle large numbers without overflow
      assert Decimal.is_decimal(result_value)
      assert Decimal.gt?(result_value, Decimal.new("999999999"))
    end

    test "handles period of 1" do
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:ok, results} = WMA.calculate(data, period: 1)
      assert length(results) == 2

      # With period 1, WMA should equal the current price (weight of 1)
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("100.0"))
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("105.0"))
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = WMA.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = WMA.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
