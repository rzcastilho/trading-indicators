defmodule TradingIndicators.Volatility.ATRTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Volatility.ATR

  alias TradingIndicators.Volatility.ATR
  alias TradingIndicators.Errors
  require Decimal

  @sample_ohlc_data [
    %{
      open: Decimal.new("44.34"),
      high: Decimal.new("44.90"),
      low: Decimal.new("44.15"),
      close: Decimal.new("44.25"),
      volume: 1000,
      timestamp: ~U[2024-01-01 09:30:00Z]
    },
    %{
      open: Decimal.new("44.25"),
      high: Decimal.new("44.83"),
      low: Decimal.new("44.05"),
      close: Decimal.new("44.30"),
      volume: 1200,
      timestamp: ~U[2024-01-01 09:31:00Z]
    },
    %{
      open: Decimal.new("44.30"),
      high: Decimal.new("44.83"),
      low: Decimal.new("43.85"),
      close: Decimal.new("44.12"),
      volume: 900,
      timestamp: ~U[2024-01-01 09:32:00Z]
    },
    %{
      open: Decimal.new("44.12"),
      high: Decimal.new("44.70"),
      low: Decimal.new("43.40"),
      close: Decimal.new("44.60"),
      volume: 1100,
      timestamp: ~U[2024-01-01 09:33:00Z]
    },
    %{
      open: Decimal.new("44.60"),
      high: Decimal.new("45.00"),
      low: Decimal.new("44.15"),
      close: Decimal.new("44.90"),
      volume: 1300,
      timestamp: ~U[2024-01-01 09:34:00Z]
    }
  ]

  describe "calculate/2" do
    test "calculates ATR with default parameters (RMA smoothing)" do
      {:ok, results} = ATR.calculate(@sample_ohlc_data, period: 3)

      assert length(results) == 3
      [first, second, third] = results

      # Check structure
      assert %{value: value1, timestamp: timestamp1, metadata: metadata1} = first
      assert Decimal.is_decimal(value1)
      assert %DateTime{} = timestamp1
      assert metadata1.indicator == "ATR"
      assert metadata1.period == 3
      assert metadata1.smoothing == :rma

      # Values should be positive
      assert Decimal.positive?(value1)
      assert Decimal.positive?(second.value)
      assert Decimal.positive?(third.value)

      # ATR should contain True Range in metadata
      assert Decimal.is_decimal(metadata1.true_range)
    end

    test "calculates ATR with SMA smoothing" do
      {:ok, results} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :sma)

      assert length(results) == 3
      first_result = List.first(results)
      assert first_result.metadata.smoothing == :sma

      # For SMA, each ATR value should be the simple average of the last N true ranges
      assert Decimal.positive?(first_result.value)
    end

    test "calculates ATR with EMA smoothing" do
      {:ok, results} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :ema)

      assert length(results) == 3
      first_result = List.first(results)
      assert first_result.metadata.smoothing == :ema
      assert Decimal.positive?(first_result.value)
    end

    test "different smoothing methods produce different results" do
      {:ok, sma_results} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :sma)
      {:ok, ema_results} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :ema)
      {:ok, rma_results} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :rma)

      assert length(sma_results) == length(ema_results)
      assert length(ema_results) == length(rma_results)

      # Values should generally be different (especially for later periods)
      last_sma = List.last(sma_results).value
      last_ema = List.last(ema_results).value
      last_rma = List.last(rma_results).value

      # At least one should be different from the others
      different_values = [last_sma, last_ema, last_rma] |> Enum.uniq() |> length()
      assert different_values > 1
    end

    test "returns error for insufficient data" do
      short_data = Enum.take(@sample_ohlc_data, 2)
      {:error, error} = ATR.calculate(short_data, period: 5)

      assert %Errors.InsufficientData{} = error
      assert error.required == 5
      assert error.provided == 2
    end

    test "returns error for invalid period" do
      {:error, error} = ATR.calculate(@sample_ohlc_data, period: 0)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = ATR.calculate(@sample_ohlc_data, period: -1)
      assert %Errors.InvalidParams{param: :period} = error
    end

    test "returns error for invalid smoothing method" do
      {:error, error} = ATR.calculate(@sample_ohlc_data, period: 3, smoothing: :invalid)
      assert %Errors.InvalidParams{param: :smoothing} = error
    end

    test "returns error for missing OHLC fields" do
      invalid_data = [%{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      {:error, error} = ATR.calculate(invalid_data, period: 1)
      assert %Errors.InvalidDataFormat{} = error
    end
  end

  describe "validate_params/1" do
    test "validates correct parameters" do
      assert :ok = ATR.validate_params(period: 14)
      assert :ok = ATR.validate_params(period: 10, smoothing: :sma)
      assert :ok = ATR.validate_params(period: 21, smoothing: :ema)
    end

    test "rejects invalid parameters" do
      {:error, error} = ATR.validate_params(period: 0)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = ATR.validate_params(smoothing: :invalid)
      assert %Errors.InvalidParams{param: :smoothing} = error
    end

    test "rejects non-keyword list" do
      {:error, error} = ATR.validate_params("not a keyword list")
      assert %Errors.InvalidParams{param: :opts} = error
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default required periods" do
      assert ATR.required_periods() == 14
    end

    test "returns configured required periods" do
      assert ATR.required_periods(period: 7) == 7
      assert ATR.required_periods(period: 21) == 21
    end
  end

  describe "streaming support" do
    test "init_state/1 creates initial state" do
      state = ATR.init_state(period: 5, smoothing: :rma)

      assert %{
               period: 5,
               smoothing: :rma,
               true_ranges: [],
               atr_value: nil,
               previous_close: nil,
               count: 0
             } = state
    end

    test "update_state/2 processes data points correctly" do
      state = ATR.init_state(period: 3, smoothing: :sma)

      # Add first data point - should not return result yet (need period data points)
      data_point1 = List.first(@sample_ohlc_data)
      {:ok, new_state1, nil} = ATR.update_state(state, data_point1)
      assert new_state1.count == 1
      assert length(new_state1.true_ranges) == 1
      assert new_state1.previous_close == data_point1.close

      # Add second data point - still not enough
      data_point2 = Enum.at(@sample_ohlc_data, 1)
      {:ok, new_state2, nil} = ATR.update_state(new_state1, data_point2)
      assert new_state2.count == 2
      assert length(new_state2.true_ranges) == 2

      # Add third data point - should return first result
      data_point3 = Enum.at(@sample_ohlc_data, 2)
      {:ok, new_state3, result} = ATR.update_state(new_state2, data_point3)

      assert new_state3.count == 3
      assert %{value: value, timestamp: timestamp, metadata: metadata} = result
      assert Decimal.is_decimal(value)
      assert Decimal.positive?(value)
      assert %DateTime{} = timestamp
      assert metadata.indicator == "ATR"
    end

    test "update_state/2 maintains rolling window for SMA" do
      state = ATR.init_state(period: 2, smoothing: :sma)

      # Fill initial window
      {:ok, state, _} = ATR.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, result1} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 1))

      assert length(state.true_ranges) == 2
      assert result1 != nil

      # Add another point - should maintain window size of 2 for SMA
      {:ok, state, result2} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 2))

      assert length(state.true_ranges) == 2
      assert result2 != nil
      # Values should be different
      refute Decimal.eq?(result1.value, result2.value)
    end

    test "update_state/2 handles EMA smoothing" do
      state = ATR.init_state(period: 2, smoothing: :ema)

      {:ok, state, _} = ATR.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, result1} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 1))
      {:ok, _state, result2} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 2))

      assert result1 != nil
      assert result2 != nil
      assert result1.metadata.smoothing == :ema
      assert result2.metadata.smoothing == :ema
    end

    test "update_state/2 handles RMA smoothing (Wilder's method)" do
      state = ATR.init_state(period: 2, smoothing: :rma)

      {:ok, state, _} = ATR.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, result1} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 1))
      {:ok, _state, result2} = ATR.update_state(state, Enum.at(@sample_ohlc_data, 2))

      assert result1 != nil
      assert result2 != nil
      assert result1.metadata.smoothing == :rma
      assert result2.metadata.smoothing == :rma
    end

    test "update_state/2 handles invalid state" do
      {:error, error} = ATR.update_state(%{invalid: :state}, List.first(@sample_ohlc_data))
      assert %Errors.StreamStateError{} = error
    end

    test "update_state/2 handles invalid data point" do
      state = ATR.init_state(period: 3)
      # Missing high/low
      invalid_data = %{close: Decimal.new("100")}

      {:error, error} = ATR.update_state(state, invalid_data)
      assert %Errors.StreamStateError{} = error
    end
  end

  describe "true range calculation" do
    test "calculates correct true range values" do
      # First data point - True Range = High - Low
      data1 = List.first(@sample_ohlc_data)
      expected_tr1 = Decimal.sub(data1.high, data1.low)

      {:ok, results} = ATR.calculate([data1], period: 1)
      result1 = List.first(results)

      assert Decimal.eq?(result1.metadata.true_range, expected_tr1)
    end

    test "true range considers previous close" do
      # Use first three data points to test previous close logic
      data = Enum.take(@sample_ohlc_data, 3)
      {:ok, results} = ATR.calculate(data, period: 2)

      # Second result should consider previous close in True Range calculation
      second_result = Enum.at(results, 1)
      assert Decimal.positive?(second_result.metadata.true_range)
      assert Decimal.positive?(second_result.value)
    end
  end

  describe "edge cases" do
    test "handles identical OHLC values" do
      identical_data = [
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("100.0"),
          low: Decimal.new("100.0"),
          close: Decimal.new("100.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("100.0"),
          low: Decimal.new("100.0"),
          close: Decimal.new("100.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = ATR.calculate(identical_data, period: 2)

      assert length(results) == 1
      result = List.first(results)
      # ATR should be 0 when there's no price movement
      assert Decimal.eq?(result.value, Decimal.new("0.0"))
    end

    test "handles minimum period of 1" do
      data = [List.first(@sample_ohlc_data)]
      {:ok, results} = ATR.calculate(data, period: 1)

      assert length(results) == 1
      assert Decimal.positive?(List.first(results).value)
    end

    test "handles large datasets efficiently" do
      large_data =
        for _i <- 1..500 do
          base_price = 100.0
          high = base_price + :rand.uniform(5)
          low = base_price - :rand.uniform(5)
          close = base_price + (:rand.uniform(10) - 5)

          %{
            open: Decimal.from_float(base_price),
            high: Decimal.from_float(high),
            low: Decimal.from_float(low),
            close: Decimal.from_float(close),
            volume: 1000,
            timestamp: DateTime.utc_now()
          }
        end

      {:ok, results} = ATR.calculate(large_data, period: 14)

      # 500 - 14 + 1
      assert length(results) == 487
      assert Enum.all?(results, &Decimal.positive?(&1.value))
    end
  end

  describe "mathematical accuracy" do
    test "SMA ATR equals simple average of true ranges" do
      # Test with known data where we can verify manually
      simple_data = [
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          open: Decimal.new("102"),
          high: Decimal.new("108"),
          low: Decimal.new("100"),
          close: Decimal.new("106"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          open: Decimal.new("106"),
          high: Decimal.new("110"),
          low: Decimal.new("103"),
          close: Decimal.new("107"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = ATR.calculate(simple_data, period: 2, smoothing: :sma)

      # For SMA with period 2, the second result should be average of TRs from windows 2-3
      # First TR = 105 - 95 = 10
      # Second TR = max(108-100, |108-102|, |100-102|) = max(8, 6, 2) = 8  
      # Third TR = max(110-103, |110-106|, |103-106|) = max(7, 4, 3) = 7
      # Second ATR (window 2-3) = (8 + 7) / 2 = 7.5
      second_result = Enum.at(results, 1)
      expected_atr = Decimal.new("7.5")

      assert Decimal.eq?(Decimal.round(second_result.value, 1), expected_atr)
    end

    test "true range calculation accuracy" do
      # Test specific true range scenarios
      prev_close = Decimal.new("50.0")

      data_point = %{
        open: Decimal.new("52.0"),
        high: Decimal.new("55.0"),
        # Gap down from previous close
        low: Decimal.new("48.0"),
        close: Decimal.new("54.0"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      # True Range = max(55-48, |55-50|, |48-50|) = max(7, 5, 2) = 7
      state = ATR.init_state(period: 1)
      state = %{state | previous_close: prev_close, count: 1}

      {:ok, _new_state, result} = ATR.update_state(state, data_point)

      expected_tr = Decimal.new("7.0")
      assert Decimal.eq?(result.metadata.true_range, expected_tr)
    end
  end

  describe "parameter_metadata/0" do
    test "returns correct parameter metadata" do
      metadata = ATR.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 2

      # Verify period parameter
      period_param = Enum.find(metadata, fn p -> p.name == :period end)
      assert period_param != nil
      assert period_param.type == :integer
      assert period_param.default == 14
      assert period_param.required == false
      assert period_param.min == 1
      assert period_param.max == nil

      # Verify smoothing parameter
      smoothing_param = Enum.find(metadata, fn p -> p.name == :smoothing end)
      assert smoothing_param != nil
      assert smoothing_param.type == :atom
      assert smoothing_param.default == :rma
      assert smoothing_param.options == [:sma, :rma, :ema]
    end

    test "all metadata maps have required fields" do
      metadata = ATR.parameter_metadata()

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
end
