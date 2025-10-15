defmodule TradingIndicators.Volume.ChaikinMoneyFlowTest do
  use ExUnit.Case, async: true
  alias TradingIndicators.Volume.ChaikinMoneyFlow
  require Decimal

  doctest ChaikinMoneyFlow

  @test_data [
    %{
      high: Decimal.new("105"),
      low: Decimal.new("99"),
      close: Decimal.new("103"),
      volume: 1000,
      timestamp: ~U[2024-01-01 09:30:00Z]
    },
    %{
      high: Decimal.new("107"),
      low: Decimal.new("102"),
      close: Decimal.new("106"),
      volume: 1500,
      timestamp: ~U[2024-01-01 09:31:00Z]
    },
    %{
      high: Decimal.new("108"),
      low: Decimal.new("104"),
      close: Decimal.new("105"),
      volume: 800,
      timestamp: ~U[2024-01-01 09:32:00Z]
    },
    %{
      high: Decimal.new("109"),
      low: Decimal.new("103"),
      close: Decimal.new("107"),
      volume: 1200,
      timestamp: ~U[2024-01-01 09:33:00Z]
    }
  ]

  describe "calculate/2" do
    test "calculates CMF correctly for basic data series with default period" do
      # Need at least 20 periods for default calculation
      data = generate_test_data(25)

      {:ok, results} = ChaikinMoneyFlow.calculate(data, [])

      # Should get results for the last 6 periods (25 - 20 + 1)
      assert length(results) == 6

      # All results should be valid CMF values between -1 and 1
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value)
        # >= -1
        assert Decimal.compare(result.value, Decimal.new("-1")) != :lt
        # <= 1
        assert Decimal.compare(result.value, Decimal.new("1")) != :gt
      end)
    end

    test "calculates CMF correctly with custom period" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("108"),
          low: Decimal.new("104"),
          close: Decimal.new("105"),
          volume: 800,
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      # Should get results for the last 2 periods (3 - 2 + 1 = 2)
      assert length(results) == 2

      # First result (periods 1-2)
      # Period 1: MF Multiplier = ((103-99) - (105-103)) / (105-99) = (4-2)/6 = 1/3
      # Period 1: MF Volume = 1/3 * 1000 = 333.333333
      # Period 2: MF Multiplier = ((106-102) - (107-106)) / (107-102) = (4-1)/5 = 3/5 = 0.6
      # Period 2: MF Volume = 0.6 * 1500 = 900
      # CMF = (333.333333 + 900) / (1000 + 1500) = 1233.333333 / 2500 = 0.4933333333
      first = Enum.at(results, 0)
      expected_first = Decimal.div(Decimal.new("1233.333333"), Decimal.new("2500"))
      assert Decimal.equal?(Decimal.round(first.value, 6), Decimal.round(expected_first, 6))

      # Second result (periods 2-3)
      # Period 3: MF Multiplier = ((105-104) - (108-105)) / (108-104) = (1-3)/4 = -0.5  
      # Period 3: MF Volume = -0.5 * 800 = -400
      # CMF = (900 + (-400)) / (1500 + 800) = 500 / 2300 = 0.2173913043
      second = Enum.at(results, 1)
      expected_second = Decimal.div(Decimal.new("500"), Decimal.new("2300"))
      assert Decimal.equal?(Decimal.round(second.value, 6), Decimal.round(expected_second, 6))
    end

    test "handles equal high and low prices (no price range)" do
      data = [
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("102"),
          low: Decimal.new("101"),
          close: Decimal.new("101"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      assert length(results) == 1

      # First period: MF Volume = 0 (High = Low)
      # Second period: MF Multiplier = ((101-101) - (102-101)) / (102-101) = -1
      # Second period: MF Volume = -1 * 1500 = -1500
      # CMF = (0 + (-1500)) / (1000 + 1500) = -1500 / 2500 = -0.6
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("-0.600000"))
    end

    test "handles close at high (bullish signal)" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("105"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("107"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      # Both periods have close at high, so MF Multiplier = 1 for both
      # CMF = (1*1000 + 1*1500) / (1000+1500) = 2500/2500 = 1.0 (maximum bullish)
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("1.000000"))
    end

    test "handles close at low (bearish signal)" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("99"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("102"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      # Both periods have close at low, so MF Multiplier = -1 for both
      # CMF = (-1*1000 + -1*1500) / (1000+1500) = -2500/2500 = -1.0 (maximum bearish)
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("-1.000000"))
    end

    test "handles zero volume periods" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 0,
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("108"),
          low: Decimal.new("104"),
          close: Decimal.new("105"),
          volume: 800,
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 3)

      assert length(results) == 1

      # Zero volume period contributes 0 to both numerator and denominator
      # CMF calculation only includes periods 1 and 3
      result = Enum.at(results, 0)
      assert Decimal.is_decimal(result.value)
    end

    test "includes correct metadata" do
      data = @test_data |> Enum.take(3)

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      result = Enum.at(results, 0)
      assert result.metadata.indicator == "ChaikinMoneyFlow"
      assert result.metadata.period == 2
      assert Decimal.is_decimal(result.metadata.money_flow_volume_sum)
      assert Decimal.is_decimal(result.metadata.volume_sum)
      assert Decimal.is_decimal(result.metadata.current_money_flow_volume)
      assert is_integer(result.metadata.volume)
      assert Decimal.equal?(result.metadata.close, Decimal.new("106"))
      assert Decimal.equal?(result.metadata.high, Decimal.new("107"))
      assert Decimal.equal?(result.metadata.low, Decimal.new("102"))
    end

    test "returns error or empty results for insufficient data" do
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} =
               ChaikinMoneyFlow.calculate([], period: 1)

      assert {:error, %TradingIndicators.Errors.InsufficientData{}} =
               ChaikinMoneyFlow.calculate(@test_data |> Enum.take(1), period: 2)
    end

    test "returns error for insufficient data with default period" do
      # Only 4 data points, need 20
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} =
               ChaikinMoneyFlow.calculate(@test_data, [])
    end

    test "returns error for invalid period" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.calculate(@test_data, period: 0)

      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.calculate(@test_data, period: -1)
    end

    test "returns error for invalid data format" do
      invalid_data = [%{price: Decimal.new("100"), vol: 1000}]

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               ChaikinMoneyFlow.calculate(invalid_data, period: 1)
    end

    test "returns error for negative prices" do
      invalid_data = [
        %{
          high: Decimal.new("-105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               ChaikinMoneyFlow.calculate(invalid_data, period: 1)
    end

    test "returns error for negative volume" do
      invalid_data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: -1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               ChaikinMoneyFlow.calculate(invalid_data, period: 1)
    end

    test "returns error for high < low" do
      invalid_data = [
        %{
          high: Decimal.new("99"),
          low: Decimal.new("105"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               ChaikinMoneyFlow.calculate(invalid_data, period: 1)
    end
  end

  describe "validate_params/1" do
    test "accepts valid period" do
      assert :ok == ChaikinMoneyFlow.validate_params(period: 1)
      assert :ok == ChaikinMoneyFlow.validate_params(period: 20)
      # Uses default
      assert :ok == ChaikinMoneyFlow.validate_params([])
    end

    test "rejects invalid period" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.validate_params(period: 0)

      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.validate_params(period: -1)

      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.validate_params(period: "invalid")
    end

    test "rejects non-keyword list options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               ChaikinMoneyFlow.validate_params("invalid")
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default minimum periods required" do
      assert ChaikinMoneyFlow.required_periods() == 20
    end

    test "returns custom minimum periods required" do
      assert ChaikinMoneyFlow.required_periods(period: 14) == 14
      assert ChaikinMoneyFlow.required_periods(period: 5) == 5
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes properly" do
      state = ChaikinMoneyFlow.init_state(period: 5)

      assert state.period == 5
      assert state.money_flow_volumes == []
      assert state.volumes == []
      assert state.count == 0
    end

    test "update_state/2 handles first data point" do
      state = ChaikinMoneyFlow.init_state(period: 2)

      data_point = %{
        high: Decimal.new("105"),
        low: Decimal.new("99"),
        close: Decimal.new("103"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      {:ok, new_state, result} = ChaikinMoneyFlow.update_state(state, data_point)

      assert length(new_state.money_flow_volumes) == 1
      assert length(new_state.volumes) == 1
      assert new_state.count == 1
      # Insufficient data for period=2
      assert result == nil
    end

    test "update_state/2 handles sufficient data" do
      state = ChaikinMoneyFlow.init_state(period: 2)

      # Add first data point
      data_point1 = %{
        high: Decimal.new("105"),
        low: Decimal.new("99"),
        close: Decimal.new("103"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      {:ok, state1, result1} = ChaikinMoneyFlow.update_state(state, data_point1)
      assert result1 == nil

      # Add second data point
      data_point2 = %{
        high: Decimal.new("107"),
        low: Decimal.new("102"),
        close: Decimal.new("106"),
        volume: 1500,
        timestamp: ~U[2024-01-01 09:31:00Z]
      }

      {:ok, state2, result2} = ChaikinMoneyFlow.update_state(state1, data_point2)

      assert length(state2.money_flow_volumes) == 2
      assert length(state2.volumes) == 2
      assert state2.count == 2
      assert result2 != nil
      assert Decimal.is_decimal(result2.value)

      # CMF should be the same as calculated in batch mode
      expected_cmf = Decimal.div(Decimal.new("1233.333333"), Decimal.new("2500"))
      assert Decimal.equal?(Decimal.round(result2.value, 6), Decimal.round(expected_cmf, 6))
    end

    test "update_state/2 maintains sliding window" do
      state = ChaikinMoneyFlow.init_state(period: 2)

      # Add three data points
      data_points = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("108"),
          low: Decimal.new("104"),
          close: Decimal.new("105"),
          volume: 800,
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      final_state =
        data_points
        |> Enum.reduce(state, fn data_point, acc_state ->
          {:ok, new_state, _result} = ChaikinMoneyFlow.update_state(acc_state, data_point)
          new_state
        end)

      # Should only keep the last 2 periods
      assert length(final_state.money_flow_volumes) == 2
      assert length(final_state.volumes) == 2
      assert final_state.count == 3
    end

    test "update_state/2 handles invalid state" do
      invalid_state = %{invalid: true}

      data_point = %{
        high: Decimal.new("105"),
        low: Decimal.new("99"),
        close: Decimal.new("103"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               ChaikinMoneyFlow.update_state(invalid_state, data_point)
    end

    test "update_state/2 handles invalid data point" do
      state = ChaikinMoneyFlow.init_state(period: 2)
      invalid_data = %{price: 100, vol: 1000}

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               ChaikinMoneyFlow.update_state(state, invalid_data)
    end
  end

  describe "edge cases and robustness" do
    test "handles large volume numbers" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 10_000_000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 20_000_000,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      assert length(results) == 1
      # Should maintain precision even with large numbers
      result = Enum.at(results, 0)
      assert Decimal.is_decimal(result.value)
      assert Decimal.compare(result.value, Decimal.new("-1")) != :lt
      assert Decimal.compare(result.value, Decimal.new("1")) != :gt
    end

    test "handles precise decimal calculations" do
      data = [
        %{
          high: Decimal.new("105.123456"),
          low: Decimal.new("99.123456"),
          close: Decimal.new("103.123456"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107.654321"),
          low: Decimal.new("102.654321"),
          close: Decimal.new("106.654321"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      assert length(results) == 1
      # Verify precision is maintained
      result = Enum.at(results, 0)
      assert Decimal.is_decimal(result.value)
    end

    test "handles all zero volume periods" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 0,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 0,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 2)

      assert length(results) == 1
      # When all volumes are zero, CMF should be 0
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("0.000000"))
    end

    test "handles period of 1" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("102"),
          close: Decimal.new("106"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ChaikinMoneyFlow.calculate(data, period: 1)

      # Should get 2 results, each CMF equals the Money Flow Multiplier of that period
      assert length(results) == 2

      # First: MF Multiplier = ((103-99) - (105-103)) / (105-99) = 1/3
      first = Enum.at(results, 0)
      expected_first = Decimal.div(Decimal.new("1"), Decimal.new("3"))
      assert Decimal.equal?(first.value, expected_first)

      # Second: MF Multiplier = ((106-102) - (107-106)) / (107-102) = 3/5
      second = Enum.at(results, 1)
      expected_second = Decimal.div(Decimal.new("3"), Decimal.new("5"))
      assert Decimal.equal?(second.value, expected_second)
    end
  end

  # Helper function to generate test data
  defp generate_test_data(count) do
    1..count
    |> Enum.map(fn i ->
      base = 100 + i

      %{
        high: Decimal.new("#{base + 2}"),
        low: Decimal.new("#{base - 2}"),
        close: Decimal.new("#{base}"),
        volume: 1000 + i * 10,
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :second)
      }
    end)
  end
end
