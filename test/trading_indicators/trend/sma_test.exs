defmodule TradingIndicators.Trend.SMATest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.SMA

  alias TradingIndicators.Trend.SMA
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

    test "calculates SMA correctly with default period", %{data: data} do
      # Use shorter data for testing with default period
      short_data = Enum.take(data, 3)
      assert {:ok, results} = SMA.calculate(short_data, period: 2)

      assert length(results) == 2

      [first, second] = results

      # First SMA: (103 + 105) / 2 = 104
      assert Decimal.equal?(first.value, Decimal.new("104.0"))
      assert first.timestamp == ~U[2024-01-01 09:31:00Z]
      assert first.metadata.indicator == "SMA"
      assert first.metadata.period == 2

      # Second SMA: (105 + 107) / 2 = 106
      assert Decimal.equal?(second.value, Decimal.new("106.0"))
      assert second.timestamp == ~U[2024-01-01 09:32:00Z]
    end

    test "calculates SMA with custom period", %{data: data} do
      assert {:ok, results} = SMA.calculate(data, period: 3)

      assert length(results) == 3

      [first, second, third] = results

      # First SMA: (103 + 105 + 107) / 3 = 105
      assert Decimal.equal?(first.value, Decimal.new("105.0"))

      # Second SMA: (105 + 107 + 106) / 3 = 106
      assert Decimal.equal?(second.value, Decimal.new("106.0"))

      # Third SMA: (107 + 106 + 108) / 3 = 107
      assert Decimal.equal?(third.value, Decimal.new("107.0"))
    end

    test "works with different price sources", %{data: data} do
      assert {:ok, high_results} = SMA.calculate(data, period: 2, source: :high)
      assert {:ok, low_results} = SMA.calculate(data, period: 2, source: :low)
      assert {:ok, open_results} = SMA.calculate(data, period: 2, source: :open)
      assert {:ok, volume_results} = SMA.calculate(data, period: 2, source: :volume)

      assert length(high_results) == 4
      assert length(low_results) == 4
      assert length(open_results) == 4
      assert length(volume_results) == 4

      # First high SMA: (105 + 107) / 2 = 106
      assert Decimal.equal?(Enum.at(high_results, 0).value, Decimal.new("106.0"))

      # First low SMA: (98 + 101) / 2 = 99.5
      assert Decimal.equal?(Enum.at(low_results, 0).value, Decimal.new("99.5"))

      # First open SMA: (100 + 103) / 2 = 101.5
      assert Decimal.equal?(Enum.at(open_results, 0).value, Decimal.new("101.5"))

      # First volume SMA: (1000 + 1200) / 2 = 1100
      assert Decimal.equal?(Enum.at(volume_results, 0).value, Decimal.new("1100.0"))
    end

    test "handles price series input", %{data: data} do
      closes = Enum.map(data, & &1.close)
      assert {:ok, results} = SMA.calculate(closes, period: 2)

      assert length(results) == 4
      # When using price series, timestamps default to current time
      assert is_struct(Enum.at(results, 0).timestamp, DateTime)
    end

    test "returns error for insufficient data", %{data: data} do
      short_data = Enum.take(data, 2)
      assert {:error, %Errors.InsufficientData{} = error} = SMA.calculate(short_data, period: 5)

      assert error.required == 5
      assert error.provided == 2
    end

    test "returns error for empty data" do
      assert {:error, %Errors.InsufficientData{}} = SMA.calculate([], period: 1)
    end

    test "returns error for invalid period" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = SMA.calculate(data, period: 0)
      assert {:error, %Errors.InvalidParams{}} = SMA.calculate(data, period: -1)
      assert {:error, %Errors.InvalidParams{}} = SMA.calculate(data, period: "invalid")
    end

    test "returns error for invalid source" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = SMA.calculate(data, source: :invalid)
    end

    test "maintains precision in calculations" do
      # Create data that would cause floating point precision issues
      data = [
        %{close: Decimal.new("0.1"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.2"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("0.3"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      assert {:ok, results} = SMA.calculate(data, period: 3)

      # Should be exactly 0.2, not a floating point approximation
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("0.2"))
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == SMA.validate_params(period: 14, source: :close)
      assert :ok == SMA.validate_params(period: 1, source: :high)
      assert :ok == SMA.validate_params([])
    end

    test "rejects invalid period" do
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(period: 0)
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(period: -5)
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(period: "10")
    end

    test "rejects invalid source" do
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(source: :invalid)
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(source: "close")
    end

    test "rejects non-keyword list" do
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params("invalid")
      assert {:error, %Errors.InvalidParams{}} = SMA.validate_params(%{period: 10})
    end
  end

  describe "required_periods/0" do
    test "returns default period" do
      assert SMA.required_periods() == 20
    end
  end

  describe "required_periods/1" do
    test "returns configured period" do
      assert SMA.required_periods(period: 14) == 14
      assert SMA.required_periods(period: 50) == 50
    end

    test "returns default for empty options" do
      assert SMA.required_periods([]) == 20
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = SMA.init_state(period: 10, source: :high)

      assert state.period == 10
      assert state.source == :high
      assert state.prices == []
      assert state.count == 0
    end

    test "init_state/1 uses defaults" do
      state = SMA.init_state()

      assert state.period == 20
      assert state.source == :close
    end

    test "update_state/2 accumulates data until period is reached" do
      state = SMA.init_state(period: 3, source: :close)

      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, state1, result1} = SMA.update_state(state, data_point1)

      # Insufficient data
      assert result1 == nil
      assert state1.count == 1
      assert length(state1.prices) == 1

      data_point2 = %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, state2, result2} = SMA.update_state(state1, data_point2)

      # Still insufficient data
      assert result2 == nil
      assert state2.count == 2
      assert length(state2.prices) == 2

      data_point3 = %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      {:ok, state3, result3} = SMA.update_state(state2, data_point3)

      # Now we have enough data
      assert result3 != nil
      assert state3.count == 3
      assert length(state3.prices) == 3
      # (100 + 102 + 104) / 3
      assert Decimal.equal?(result3.value, Decimal.new("102.0"))
    end

    test "update_state/2 maintains rolling window" do
      state = SMA.init_state(period: 2, source: :close)

      # Add first two points
      {:ok, state, _} =
        SMA.update_state(state, %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]})

      {:ok, state, result} =
        SMA.update_state(state, %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]})

      # (100 + 102) / 2
      assert Decimal.equal?(result.value, Decimal.new("101.00"))

      # Add third point - should maintain window size of 2
      {:ok, state, result} =
        SMA.update_state(state, %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]})

      # Window size maintained
      assert length(state.prices) == 2
      # (102 + 104) / 2
      assert Decimal.equal?(result.value, Decimal.new("103.00"))
    end

    test "update_state/2 works with price values directly" do
      # Note: When using price values directly, they must match the configured source field
      # For this test, we'll use OHLCV data points with the expected structure
      state = SMA.init_state(period: 2, source: :close)

      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      data_point2 = %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}

      {:ok, state, _} = SMA.update_state(state, data_point1)
      {:ok, _state, result} = SMA.update_state(state, data_point2)

      assert Decimal.equal?(result.value, Decimal.new("101.00"))
    end

    test "update_state/2 handles different sources" do
      state = SMA.init_state(period: 2, source: :high)

      data_point1 = %{high: Decimal.new("105"), timestamp: ~U[2024-01-01 09:30:00Z]}
      data_point2 = %{high: Decimal.new("107"), timestamp: ~U[2024-01-01 09:31:00Z]}

      {:ok, state, _} = SMA.update_state(state, data_point1)
      {:ok, _state, result} = SMA.update_state(state, data_point2)

      # (105 + 107) / 2
      assert Decimal.equal?(result.value, Decimal.new("106.0"))
      assert result.metadata.source == :high
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}

      assert {:error, %Errors.StreamStateError{}} = SMA.update_state(invalid_state, data_point)
    end
  end

  describe "edge cases and robustness" do
    test "handles very large numbers" do
      data = [
        %{close: Decimal.new("999999999.99"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("1000000000.01"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:ok, results} = SMA.calculate(data, period: 2)
      # Average of the two
      expected = Decimal.new("1000000000.0")
      assert Decimal.equal?(Enum.at(results, 0).value, expected)
    end

    test "handles very small numbers" do
      data = [
        %{close: Decimal.new("0.00000001"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.00000002"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:ok, results} = SMA.calculate(data, period: 2)
      expected = Decimal.new("0.000000015")
      assert Decimal.equal?(Enum.at(results, 0).value, expected)
    end

    test "handles period of 1" do
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:ok, results} = SMA.calculate(data, period: 1)
      assert length(results) == 2

      # With period 1, SMA should equal the close price
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("100.0"))
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("105.0"))
    end
  end

  describe "property-based testing" do
    test "SMA values are within reasonable bounds" do
      # Test with fixed test data rather than property-based for now
      # to avoid StreamData dependency issues

      periods = [1, 2, 3, 5]
      test_price = Decimal.new("100.0")

      for period <- periods do
        # Create data with constant price
        data =
          for i <- 1..(period + 5) do
            %{
              close: test_price,
              timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
            }
          end

        {:ok, results} = SMA.calculate(data, period: period)

        # All SMA values should equal the constant price
        Enum.each(results, fn result ->
          assert Decimal.equal?(result.value, test_price)
        end)
      end
    end

    test "SMA values are between min and max of contributing prices" do
      # Create test data with varying prices
      prices = [100, 102, 98, 104, 96, 106, 94, 108]

      data =
        for {price, i} <- Enum.with_index(prices, 1) do
          %{
            close: Decimal.new(to_string(price)),
            timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
          }
        end

      period = 3
      {:ok, results} = SMA.calculate(data, period: period)

      # Each SMA should be within the range of its contributing window
      results
      |> Enum.with_index(period - 1)
      |> Enum.each(fn {result, index} ->
        window_start = index - period + 1

        window_prices =
          data
          |> Enum.slice(window_start, period)
          |> Enum.map(& &1.close)

        min_price = Enum.min(window_prices)
        max_price = Enum.max(window_prices)

        assert Decimal.gte?(result.value, min_price)
        assert Decimal.lte?(result.value, max_price)
      end)
    end
  end

  describe "parameter_metadata/0" do
    test "returns correct parameter metadata" do
      metadata = SMA.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 2

      # Verify period parameter
      period_param = Enum.find(metadata, fn p -> p.name == :period end)
      assert period_param != nil
      assert period_param.type == :integer
      assert period_param.default == 20
      assert period_param.required == false
      assert period_param.min == 1
      assert period_param.max == nil
      assert period_param.options == nil
      assert period_param.description == "Number of periods to use in SMA calculation"

      # Verify source parameter
      source_param = Enum.find(metadata, fn p -> p.name == :source end)
      assert source_param != nil
      assert source_param.type == :atom
      assert source_param.default == :close
      assert source_param.required == false
      assert source_param.min == nil
      assert source_param.max == nil
      assert source_param.options == [:open, :high, :low, :close, :volume]
      assert source_param.description == "Source price field to use"
    end

    test "all metadata maps have required fields" do
      metadata = SMA.parameter_metadata()

      Enum.each(metadata, fn param ->
        assert Map.has_key?(param, :name)
        assert Map.has_key?(param, :type)
        assert Map.has_key?(param, :default)
        assert Map.has_key?(param, :required)
        assert Map.has_key?(param, :min)
        assert Map.has_key?(param, :max)
        assert Map.has_key?(param, :options)
        assert Map.has_key?(param, :description)
      end)
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = SMA.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = SMA.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
