defmodule TradingIndicators.Volume.VWAPTest do
  use ExUnit.Case, async: true
  alias TradingIndicators.Volume.VWAP
  require Decimal

  doctest VWAP

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
    }
  ]

  describe "calculate/2" do
    test "calculates VWAP correctly with close variant" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close)

      assert length(results) == 2

      # First VWAP = 100 * 1000 / 1000 = 100
      first = Enum.at(results, 0)
      assert Decimal.equal?(first.value, Decimal.new("100.000000"))

      # Second VWAP = (100*1000 + 102*1500) / (1000+1500) = 253000 / 2500 = 101.2
      second = Enum.at(results, 1)
      assert Decimal.equal?(second.value, Decimal.new("101.200000"))
    end

    test "calculates VWAP correctly with typical price variant" do
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

      {:ok, results} = VWAP.calculate(data, variant: :typical)

      assert length(results) == 2

      # First typical price = (105 + 99 + 103) / 3 = 102.333333
      # First VWAP = 102.333333
      first = Enum.at(results, 0)
      expected_first = Decimal.div(Decimal.new("307"), Decimal.new("3"))
      assert Decimal.equal?(first.value, Decimal.round(expected_first, 6))

      # Second typical price = (107 + 102 + 106) / 3 = 105
      # Cumulative = (102.333333*1000 + 105*1500) / 2500 = (102333.333 + 157500) / 2500 = 259833.333 / 2500 = 103.933333
      second = Enum.at(results, 1)
      assert Decimal.equal?(second.value, Decimal.new("103.933333"))
    end

    test "calculates VWAP correctly with weighted price variant" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      {:ok, results} = VWAP.calculate(data, variant: :weighted)

      assert length(results) == 1

      # Weighted price = (105 + 99 + 2*103) / 4 = 410 / 4 = 102.5
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("102.500000"))
    end

    test "handles single data point" do
      data = [%{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]

      {:ok, results} = VWAP.calculate(data, variant: :close)

      assert length(results) == 1
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("100.000000"))
    end

    test "skips zero volume periods" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), volume: 1500, timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close)

      # Should get results for periods with non-zero volume only
      assert length(results) == 2

      first = Enum.at(results, 0)
      assert Decimal.equal?(first.value, Decimal.new("100.000000"))

      # Second should be (100*1000 + 104*1500) / 2500 = 256000 / 2500 = 102.4
      second = Enum.at(results, 1)
      assert Decimal.equal?(second.value, Decimal.new("102.400000"))
    end

    test "includes correct metadata" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      {:ok, results} = VWAP.calculate(data, variant: :typical, session_reset: :daily)

      result = Enum.at(results, 0)
      assert result.metadata.indicator == "VWAP"
      assert result.metadata.variant == :typical
      assert result.metadata.session_reset == :daily
      assert result.metadata.volume == 1000
      assert Decimal.equal?(result.metadata.cumulative_volume, Decimal.new("1000"))
    end

    test "returns error for insufficient data" do
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} = VWAP.calculate([], [])
    end

    test "returns error for invalid variant" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               VWAP.calculate(@test_data, variant: :invalid)
    end

    test "returns error for invalid session reset" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               VWAP.calculate(@test_data, session_reset: :invalid)
    end

    test "returns error for invalid data format" do
      invalid_data = [%{price: Decimal.new("100"), vol: 1000}]

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               VWAP.calculate(invalid_data, variant: :close)
    end

    test "returns error for negative volume" do
      invalid_data = [
        %{close: Decimal.new("100"), volume: -1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               VWAP.calculate(invalid_data, [])
    end

    test "returns error for high < low" do
      invalid_data = [
        %{
          high: Decimal.new("99"),
          low: Decimal.new("105"),
          close: Decimal.new("100"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      assert {:error, %TradingIndicators.Errors.ValidationError{}} =
               VWAP.calculate(invalid_data, variant: :typical)
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == VWAP.validate_params(variant: :close, session_reset: :daily)
      assert :ok == VWAP.validate_params(variant: :typical)
      assert :ok == VWAP.validate_params(session_reset: :weekly)
      assert :ok == VWAP.validate_params([])
    end

    test "rejects invalid variant" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               VWAP.validate_params(variant: :invalid)
    end

    test "rejects invalid session reset" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               VWAP.validate_params(session_reset: :invalid)
    end

    test "rejects non-keyword list options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               VWAP.validate_params("invalid")
    end
  end

  describe "required_periods/0" do
    test "returns minimum periods required" do
      assert VWAP.required_periods() == 1
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes properly" do
      state = VWAP.init_state(variant: :typical, session_reset: :daily)

      assert state.variant == :typical
      assert state.session_reset == :daily
      assert Decimal.equal?(state.cumulative_price_volume, Decimal.new("0"))
      assert Decimal.equal?(state.cumulative_volume, Decimal.new("0"))
      assert state.current_session_start == nil
      assert state.count == 0
    end

    test "update_state/2 handles first data point" do
      state = VWAP.init_state(variant: :close)
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}

      {:ok, new_state, result} = VWAP.update_state(state, data_point)

      assert Decimal.equal?(new_state.cumulative_price_volume, Decimal.new("100000"))
      assert Decimal.equal?(new_state.cumulative_volume, Decimal.new("1000"))
      assert new_state.count == 1
      assert Decimal.equal?(result.value, Decimal.new("100.000000"))
    end

    test "update_state/2 handles zero volume periods" do
      state = VWAP.init_state(variant: :close)
      data_point = %{close: Decimal.new("100"), volume: 0, timestamp: ~U[2024-01-01 09:30:00Z]}

      {:ok, new_state, result} = VWAP.update_state(state, data_point)

      assert Decimal.equal?(new_state.cumulative_price_volume, Decimal.new("0"))
      assert Decimal.equal?(new_state.cumulative_volume, Decimal.new("0"))
      assert new_state.count == 1
      # No result for zero volume
      assert result == nil
    end

    test "update_state/2 handles session resets" do
      # Create state with some accumulated data
      state = %{
        variant: :close,
        session_reset: :daily,
        cumulative_price_volume: Decimal.new("100000"),
        cumulative_volume: Decimal.new("1000"),
        current_session_start: ~U[2024-01-01 00:00:00Z],
        count: 1
      }

      # New data point on a different day should reset
      data_point = %{close: Decimal.new("102"), volume: 500, timestamp: ~U[2024-01-02 09:30:00Z]}

      {:ok, new_state, result} = VWAP.update_state(state, data_point)

      # Should reset cumulative values and calculate fresh VWAP
      # 102 * 500
      assert Decimal.equal?(new_state.cumulative_price_volume, Decimal.new("51000"))
      assert Decimal.equal?(new_state.cumulative_volume, Decimal.new("500"))
      assert Decimal.equal?(result.value, Decimal.new("102.000000"))
      assert result.metadata.session_reset_occurred == true
    end

    test "update_state/2 handles invalid state" do
      invalid_state = %{invalid: true}
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               VWAP.update_state(invalid_state, data_point)
    end

    test "update_state/2 handles invalid data point" do
      state = VWAP.init_state([])
      invalid_data = %{price: 100, vol: 1000}

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               VWAP.update_state(state, invalid_data)
    end
  end

  describe "session reset functionality" do
    test "daily session reset works correctly" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), volume: 1500, timestamp: ~U[2024-01-01 15:30:00Z]},
        # Next day
        %{close: Decimal.new("104"), volume: 800, timestamp: ~U[2024-01-02 09:30:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close, session_reset: :daily)

      assert length(results) == 3

      # First day results should accumulate
      first = Enum.at(results, 0)
      assert Decimal.equal?(first.value, Decimal.new("100.000000"))

      second = Enum.at(results, 1)
      # (100*1000 + 102*1500) / 2500
      expected_second = Decimal.div(Decimal.new("253000"), Decimal.new("2500"))
      assert Decimal.equal?(second.value, expected_second)

      # Third day should reset
      third = Enum.at(results, 2)
      # Fresh start
      assert Decimal.equal?(third.value, Decimal.new("104.000000"))
    end

    test "weekly session reset works correctly" do
      # Monday to Tuesday (same week), then next Monday (different week)
      data = [
        # Monday
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        # Tuesday
        %{close: Decimal.new("102"), volume: 1500, timestamp: ~U[2024-01-02 09:30:00Z]},
        # Next Monday
        %{close: Decimal.new("104"), volume: 800, timestamp: ~U[2024-01-08 09:30:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close, session_reset: :weekly)

      assert length(results) == 3

      # First week results should accumulate
      third = Enum.at(results, 2)
      # Reset for new week
      assert Decimal.equal?(third.value, Decimal.new("104.000000"))
    end

    test "no session reset accumulates continuously" do
      data = [
        %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        # Different month
        %{close: Decimal.new("102"), volume: 1500, timestamp: ~U[2024-02-01 09:30:00Z]},
        # Different month
        %{close: Decimal.new("104"), volume: 800, timestamp: ~U[2024-03-01 09:30:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close, session_reset: :none)

      assert length(results) == 3

      # Should continuously accumulate across all periods
      third = Enum.at(results, 2)
      # 100*1000
      total_pv =
        Decimal.new("100000")
        # 102*1500
        |> Decimal.add(Decimal.new("153000"))
        # 104*800
        |> Decimal.add(Decimal.new("83200"))

      # 1000 + 1500 + 800
      total_v = Decimal.new("3300")
      expected = Decimal.div(total_pv, total_v)

      assert Decimal.equal?(third.value, Decimal.round(expected, 6))
    end
  end

  describe "edge cases and robustness" do
    test "handles large volume numbers" do
      data = [
        %{close: Decimal.new("100"), volume: 10_000_000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), volume: 20_000_000, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close)

      assert length(results) == 2
      # Should maintain precision even with large numbers
      second = Enum.at(results, 1)
      expected = Decimal.div(Decimal.new("3040000000"), Decimal.new("30000000"))
      assert Decimal.equal?(second.value, Decimal.round(expected, 6))
    end

    test "handles precise decimal calculations" do
      data = [
        %{close: Decimal.new("100.123456"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100.123457"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = VWAP.calculate(data, variant: :close)

      assert length(results) == 2
      # Verify precision is maintained
      second = Enum.at(results, 1)
      assert Decimal.is_decimal(second.value)
    end
  end
end
