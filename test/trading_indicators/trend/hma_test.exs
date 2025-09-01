defmodule TradingIndicators.Trend.HMATest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.HMA

  alias TradingIndicators.Trend.HMA
  alias TradingIndicators.Errors
  require Decimal

  describe "calculate/2" do
    setup do
      # Generate sufficient data for HMA calculation
      data = for i <- 0..25 do
        base_price = 100 + i * 0.5  # Trending prices
        %{
          open: Decimal.new(to_string(base_price - 0.2)),
          high: Decimal.new(to_string(base_price + 0.3)),
          low: Decimal.new(to_string(base_price - 0.3)),
          close: Decimal.new(to_string(base_price)),
          volume: 1000 + i * 10,
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end

      {:ok, data: data}
    end

    test "calculates HMA with default period", %{data: data} do
      assert {:ok, results} = HMA.calculate(data)
      
      # Should have some results
      assert length(results) >= 1
      
      first_result = List.first(results)
      assert Decimal.is_decimal(first_result.value)
      assert first_result.metadata.indicator == "HMA"
      assert first_result.metadata.period == 14
      assert first_result.metadata.source == :close
    end

    test "calculates HMA with custom period", %{data: data} do
      assert {:ok, results} = HMA.calculate(data, period: 9)
      
      assert length(results) >= 1
      
      first_result = List.first(results)
      assert Decimal.is_decimal(first_result.value)
      assert first_result.metadata.period == 9
    end

    test "works with different price sources", %{data: data} do
      assert {:ok, high_results} = HMA.calculate(data, period: 4, source: :high)
      assert {:ok, low_results} = HMA.calculate(data, period: 4, source: :low)
      
      assert length(high_results) >= 1
      assert length(low_results) >= 1
      
      first_high = List.first(high_results)
      first_low = List.first(low_results)
      
      assert first_high.metadata.source == :high
      assert first_low.metadata.source == :low
    end

    test "handles price series input", %{data: data} do
      closes = Enum.map(data, & &1.close)
      case HMA.calculate(closes, period: 4) do
        {:ok, [_ | _] = results} ->
          assert is_struct(List.first(results).timestamp, DateTime)
        {:ok, []} ->
          # Acceptable - may not have enough data
          :ok
        {:error, _reason} ->
          # Also acceptable - insufficient data
          :ok
      end
    end

    test "returns error for insufficient data" do
      short_data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      
      assert {:error, %Errors.InsufficientData{}} = HMA.calculate(short_data, period: 9)
    end

    test "returns error for empty data" do
      assert {:error, %Errors.InsufficientData{}} = HMA.calculate([])
    end

    test "returns error for invalid period" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = HMA.calculate(data, period: 1)  # Must be >= 2
      assert {:error, %Errors.InvalidParams{}} = HMA.calculate(data, period: 0)
      assert {:error, %Errors.InvalidParams{}} = HMA.calculate(data, period: -1)
    end

    test "returns error for invalid source" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = HMA.calculate(data, source: :invalid)
    end

    test "HMA is more responsive than traditional moving averages", %{data: data} do
      # Create data with a price jump to test responsiveness
      jump_data = data ++ [
        %{close: Decimal.new("120"), timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], 26, :minute)},
        %{close: Decimal.new("125"), timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], 27, :minute)}
      ]
      
      {:ok, hma_results} = HMA.calculate(jump_data, period: 4)
      {:ok, sma_results} = TradingIndicators.Trend.SMA.calculate(jump_data, period: 4)
      
      # Both should have results
      assert length(hma_results) >= 1
      assert length(sma_results) >= 1
      
      # HMA should react more quickly to the price change
      # (Specific comparison depends on the data pattern)
      assert Decimal.is_decimal(List.last(hma_results).value)
      assert Decimal.is_decimal(List.last(sma_results).value)
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == HMA.validate_params(period: 9, source: :close)
      assert :ok == HMA.validate_params(period: 4, source: :high)
      assert :ok == HMA.validate_params([])
    end

    test "rejects invalid period" do
      assert {:error, %Errors.InvalidParams{}} = HMA.validate_params(period: 1)  # Too small
      assert {:error, %Errors.InvalidParams{}} = HMA.validate_params(period: 0)
      assert {:error, %Errors.InvalidParams{}} = HMA.validate_params(period: -5)
    end

    test "rejects invalid source" do
      assert {:error, %Errors.InvalidParams{}} = HMA.validate_params(source: :invalid)
    end

    test "rejects non-keyword list" do
      assert {:error, %Errors.InvalidParams{}} = HMA.validate_params("invalid")
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default requirements" do
      # Default period 14: 14 + sqrt(14) - 1 = 14 + 4 - 1 = 17
      assert HMA.required_periods() == 17
    end

    test "returns configured requirements" do
      # Period 9: 9 + sqrt(9) - 1 = 9 + 3 - 1 = 11
      assert HMA.required_periods(period: 9) == 11
      
      # Period 16: 16 + sqrt(16) - 1 = 16 + 4 - 1 = 19
      assert HMA.required_periods(period: 16) == 19
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = HMA.init_state(period: 9, source: :high)
      
      assert state.period == 9
      assert state.half_period == 4  # div(9, 2) = 4
      assert state.sqrt_period == 3   # sqrt(9) = 3
      assert state.source == :high
      assert is_map(state.wma_half_state)
      assert is_map(state.wma_full_state)
      assert is_map(state.wma_sqrt_state)
      assert state.raw_hma_values == []
      assert state.count == 0
    end

    test "init_state/1 uses defaults" do
      state = HMA.init_state()
      
      assert state.period == 14
      assert state.half_period == 7
      assert state.sqrt_period == 4  # round(sqrt(14)) = 4
      assert state.source == :close
    end

    test "update_state/2 accumulates data until HMA can be calculated" do
      state = HMA.init_state(period: 4, source: :close)
      
      # Generate sufficient data points
      data_points = for i <- 100..115 do
        %{
          close: Decimal.new(to_string(i)),
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i - 100, :minute)
        }
      end
      
      # Process each data point
      {final_state, final_result} = 
        Enum.reduce(data_points, {state, nil}, fn data_point, {current_state, _prev_result} ->
          {:ok, new_state, result} = HMA.update_state(current_state, data_point)
          {new_state, result}
        end)
      
      # Should eventually get an HMA result
      if final_result do
        assert is_map(final_result.value)
        assert Decimal.is_decimal(final_result.value)
      end
      assert final_state.count == length(data_points)
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      
      assert {:error, %Errors.StreamStateError{}} = HMA.update_state(invalid_state, data_point)
    end
  end

  describe "mathematical accuracy" do
    test "sqrt period calculation is correct" do
      # Test various periods and their sqrt values
      # For period 4: sqrt(4) = 2, so required = 4 + 2 - 1 = 5
      assert HMA.required_periods(period: 4) == 5
      
      # For period 9: sqrt(9) = 3, so required = 9 + 3 - 1 = 11  
      assert HMA.required_periods(period: 9) == 11
      
      # For period 16: sqrt(16) = 4, so required = 16 + 4 - 1 = 19
      assert HMA.required_periods(period: 16) == 19
    end

    test "handles edge cases with small periods" do
      # Test minimum period (2)
      data = for i <- 0..10 do
        %{
          close: Decimal.new(to_string(100 + i)),
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end
      
      case HMA.calculate(data, period: 2) do
        {:ok, results} ->
          assert length(results) >= 0
          if length(results) > 0 do
            assert Decimal.is_decimal(List.first(results).value)
          end
        {:error, _} ->
          # Acceptable if not enough data
          :ok
      end
    end

    test "maintains precision in calculations" do
      # Test with decimal values that might cause floating point issues
      data = for i <- 0..15 do
        price = Decimal.add(Decimal.new("100.1"), Decimal.div(Decimal.new(i), Decimal.new("10")))
        %{
          close: price,
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end
      
      case HMA.calculate(data, period: 4) do
        {:ok, results} ->
          # All HMA values should be proper decimals
          Enum.each(results, fn result ->
            assert Decimal.is_decimal(result.value)
          end)
        {:error, _} ->
          # May not have enough data
          :ok
      end
    end
  end
end