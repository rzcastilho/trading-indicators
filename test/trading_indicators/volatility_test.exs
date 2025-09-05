defmodule TradingIndicators.VolatilityTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Volatility

  alias TradingIndicators.Volatility
  alias TradingIndicators.Volatility.{StandardDeviation, ATR, BollingerBands, VolatilityIndex}
  alias TradingIndicators.Errors
  require Decimal

  @sample_ohlcv_data [
    %{
      open: Decimal.new("100.0"),
      high: Decimal.new("105.0"),
      low: Decimal.new("99.0"),
      close: Decimal.new("103.0"),
      volume: 1000,
      timestamp: ~U[2024-01-01 09:30:00Z]
    },
    %{
      open: Decimal.new("103.0"),
      high: Decimal.new("107.0"),
      low: Decimal.new("101.0"),
      close: Decimal.new("106.0"),
      volume: 1200,
      timestamp: ~U[2024-01-01 09:31:00Z]
    },
    %{
      open: Decimal.new("106.0"),
      high: Decimal.new("108.0"),
      low: Decimal.new("104.0"),
      close: Decimal.new("105.0"),
      volume: 900,
      timestamp: ~U[2024-01-01 09:32:00Z]
    },
    %{
      open: Decimal.new("105.0"),
      high: Decimal.new("109.0"),
      low: Decimal.new("103.0"),
      close: Decimal.new("107.0"),
      volume: 1100,
      timestamp: ~U[2024-01-01 09:33:00Z]
    },
    %{
      open: Decimal.new("107.0"),
      high: Decimal.new("110.0"),
      low: Decimal.new("105.0"),
      close: Decimal.new("108.0"),
      volume: 1300,
      timestamp: ~U[2024-01-01 09:34:00Z]
    }
  ]

  @sample_price_series [
    Decimal.new("100.0"),
    Decimal.new("102.0"),
    Decimal.new("104.0"),
    Decimal.new("103.0"),
    Decimal.new("101.0"),
    Decimal.new("105.0")
  ]

  describe "available_indicators/0" do
    test "returns all volatility indicator modules" do
      indicators = Volatility.available_indicators()

      assert StandardDeviation in indicators
      assert ATR in indicators
      assert BollingerBands in indicators
      assert VolatilityIndex in indicators
      assert length(indicators) == 4
    end
  end

  describe "calculate/3" do
    test "calculates StandardDeviation through unified interface" do
      {:ok, results} = Volatility.calculate(StandardDeviation, @sample_price_series, period: 3)

      assert length(results) == 4

      assert Enum.all?(results, fn result ->
               Decimal.is_decimal(result.value) and
                 result.metadata.indicator == "STDDEV"
             end)
    end

    test "calculates ATR through unified interface" do
      {:ok, results} = Volatility.calculate(ATR, @sample_ohlcv_data, period: 3)

      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               Decimal.is_decimal(result.value) and
                 result.metadata.indicator == "ATR"
             end)
    end

    test "calculates BollingerBands through unified interface" do
      {:ok, results} = Volatility.calculate(BollingerBands, @sample_price_series, period: 3)

      assert length(results) == 4

      assert Enum.all?(results, fn result ->
               Map.has_key?(result, :upper_band) and
                 Map.has_key?(result, :middle_band) and
                 Map.has_key?(result, :lower_band) and
                 result.metadata.indicator == "BOLLINGER"
             end)
    end

    test "calculates VolatilityIndex through unified interface" do
      {:ok, results} = Volatility.calculate(VolatilityIndex, @sample_price_series, period: 3)

      # 6 - 3 - 1 + 1 (need extra for returns)
      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               Decimal.is_decimal(result.value) and
                 result.metadata.indicator == "VOLATILITY"
             end)
    end

    test "returns error for unknown indicator" do
      {:error, error} = Volatility.calculate(UnknownIndicator, @sample_price_series, period: 3)

      assert %Errors.InvalidParams{param: :indicator} = error
      assert error.value == UnknownIndicator
    end

    test "passes through indicator-specific errors" do
      # Test insufficient data error
      short_data = Enum.take(@sample_price_series, 2)
      {:error, error} = Volatility.calculate(StandardDeviation, short_data, period: 5)

      assert %Errors.InsufficientData{} = error
    end
  end

  describe "convenience functions" do
    test "standard_deviation/2 calculates StandardDeviation" do
      {:ok, results} = Volatility.standard_deviation(@sample_price_series, period: 3)

      assert length(results) == 4

      assert Enum.all?(results, fn result ->
               result.metadata.indicator == "STDDEV"
             end)
    end

    test "atr/2 calculates ATR" do
      {:ok, results} = Volatility.atr(@sample_ohlcv_data, period: 3, smoothing: :sma)

      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               result.metadata.indicator == "ATR" and
                 result.metadata.smoothing == :sma
             end)
    end

    test "bollinger_bands/2 calculates BollingerBands" do
      {:ok, results} = Volatility.bollinger_bands(@sample_price_series, period: 3, multiplier: 2.5)

      assert length(results) == 4

      assert Enum.all?(results, fn result ->
               result.metadata.indicator == "BOLLINGER" and
                 Decimal.eq?(result.metadata.multiplier, Decimal.new("2.5"))
             end)
    end

    test "volatility_index/2 calculates VolatilityIndex" do
      {:ok, results} =
        Volatility.volatility_index(@sample_price_series, period: 3, method: :historical)

      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               result.metadata.indicator == "VOLATILITY" and
                 result.metadata.method == :historical
             end)
    end
  end

  describe "streaming support" do
    test "init_stream/2 initializes state for StandardDeviation" do
      state = Volatility.init_stream(StandardDeviation, period: 5, calculation: :sample)

      assert %{period: 5, calculation: :sample, prices: [], count: 0} = state
    end

    test "init_stream/2 initializes state for ATR" do
      state = Volatility.init_stream(ATR, period: 14, smoothing: :rma)

      assert %{period: 14, smoothing: :rma, true_ranges: [], count: 0} = state
    end

    test "init_stream/2 initializes state for BollingerBands" do
      state = Volatility.init_stream(BollingerBands, period: 20, multiplier: 2.0)

      assert %{period: 20, multiplier: multiplier, prices: [], count: 0} = state
      assert Decimal.eq?(multiplier, Decimal.new("2.0"))
    end

    test "init_stream/2 initializes state for VolatilityIndex" do
      state = Volatility.init_stream(VolatilityIndex, period: 20, method: :garman_klass)

      assert %{period: 20, method: :garman_klass, data_points: [], count: 0} = state
    end

    test "init_stream/2 raises error for unknown indicator" do
      assert_raise ArgumentError, ~r/Unknown volatility indicator/, fn ->
        Volatility.init_stream(UnknownIndicator, period: 5)
      end
    end

    test "update_stream/2 updates StandardDeviation state" do
      state = Volatility.init_stream(StandardDeviation, period: 3)

      # Add data points
      {:ok, state, _} = Volatility.update_stream(state, List.first(@sample_ohlcv_data))
      {:ok, state, _} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 1))
      {:ok, _state, result} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 2))

      assert result != nil
      assert result.metadata.indicator == "STDDEV"
    end

    test "update_stream/2 updates ATR state" do
      state = Volatility.init_stream(ATR, period: 2, smoothing: :sma)

      # Add data points
      {:ok, state, _} = Volatility.update_stream(state, List.first(@sample_ohlcv_data))
      {:ok, _state, result} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 1))

      assert result != nil
      assert result.metadata.indicator == "ATR"
    end

    test "update_stream/2 updates BollingerBands state" do
      state = Volatility.init_stream(BollingerBands, period: 2)

      # Add data points
      {:ok, state, _} = Volatility.update_stream(state, List.first(@sample_ohlcv_data))
      {:ok, _state, result} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 1))

      assert result != nil
      assert result.metadata.indicator == "BOLLINGER"
    end

    test "update_stream/2 updates VolatilityIndex state" do
      state = Volatility.init_stream(VolatilityIndex, period: 2, method: :historical)

      # Add data points (need 3 for period 2 + 1 for returns)
      {:ok, state, _} = Volatility.update_stream(state, List.first(@sample_ohlcv_data))
      {:ok, state, _} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 1))
      {:ok, _state, result} = Volatility.update_stream(state, Enum.at(@sample_ohlcv_data, 2))

      assert result != nil
      assert result.metadata.indicator == "VOLATILITY"
    end

    test "update_stream/2 returns error for unknown state format" do
      invalid_state = %{unknown: :format}

      {:error, error} = Volatility.update_stream(invalid_state, List.first(@sample_ohlcv_data))

      assert %Errors.StreamStateError{} = error
      assert error.reason == "unknown state format"
    end
  end

  describe "indicator_info/1" do
    test "returns info for StandardDeviation" do
      info = Volatility.indicator_info(StandardDeviation)

      assert %{
               module: StandardDeviation,
               name: "StandardDeviation",
               required_periods: 20,
               supports_streaming: true
             } = info
    end

    test "returns info for ATR" do
      info = Volatility.indicator_info(ATR)

      assert %{
               module: ATR,
               name: "ATR",
               required_periods: 14,
               supports_streaming: true
             } = info
    end

    test "returns info for BollingerBands" do
      info = Volatility.indicator_info(BollingerBands)

      assert %{
               module: BollingerBands,
               name: "BollingerBands",
               required_periods: 20,
               supports_streaming: true
             } = info
    end

    test "returns info for VolatilityIndex" do
      info = Volatility.indicator_info(VolatilityIndex)

      assert %{
               module: VolatilityIndex,
               name: "VolatilityIndex",
               required_periods: 21,
               supports_streaming: true
             } = info
    end

    test "returns error for unknown indicator" do
      info = Volatility.indicator_info(UnknownIndicator)

      assert %{error: "Unknown indicator"} = info
    end
  end

  describe "all_indicators_info/0" do
    test "returns info for all indicators" do
      all_info = Volatility.all_indicators_info()

      assert length(all_info) == 4

      assert Enum.all?(all_info, fn info ->
               Map.has_key?(info, :module) and
                 Map.has_key?(info, :name) and
                 Map.has_key?(info, :required_periods) and
                 Map.has_key?(info, :supports_streaming)
             end)

      # Check that all expected indicators are present
      modules = Enum.map(all_info, & &1.module)
      assert StandardDeviation in modules
      assert ATR in modules
      assert BollingerBands in modules
      assert VolatilityIndex in modules
    end
  end

  describe "integration tests" do
    test "all indicators work with common OHLCV data" do
      common_data = @sample_ohlcv_data

      {:ok, stddev_results} = Volatility.standard_deviation(common_data, period: 3)
      {:ok, atr_results} = Volatility.atr(common_data, period: 3)
      {:ok, bb_results} = Volatility.bollinger_bands(common_data, period: 3)
      {:ok, vol_results} = Volatility.volatility_index(common_data, period: 3, method: :historical)

      # All should produce valid results
      assert length(stddev_results) > 0
      assert length(atr_results) > 0
      assert length(bb_results) > 0
      assert length(vol_results) > 0

      # All results should have proper structure
      assert Enum.all?(stddev_results, &Decimal.is_decimal(&1.value))
      assert Enum.all?(atr_results, &Decimal.is_decimal(&1.value))
      assert Enum.all?(bb_results, &Map.has_key?(&1, :upper_band))
      assert Enum.all?(vol_results, &Decimal.is_decimal(&1.value))
    end

    test "streaming works across all indicators" do
      # Test that we can create streaming states for all indicators
      # and process at least one data point successfully
      stddev_state = Volatility.init_stream(StandardDeviation, period: 2)
      atr_state = Volatility.init_stream(ATR, period: 2)
      bb_state = Volatility.init_stream(BollingerBands, period: 2)
      vol_state = Volatility.init_stream(VolatilityIndex, period: 2)

      data_point = List.first(@sample_ohlcv_data)

      # All should accept the data point without error
      {:ok, _stddev_state2, _} = Volatility.update_stream(stddev_state, data_point)
      {:ok, _atr_state2, _} = Volatility.update_stream(atr_state, data_point)
      {:ok, _bb_state2, _} = Volatility.update_stream(bb_state, data_point)
      {:ok, _vol_state2, _} = Volatility.update_stream(vol_state, data_point)
    end

    test "error handling works consistently across indicators" do
      # Test that all indicators handle insufficient data consistently
      short_data = [List.first(@sample_ohlcv_data)]

      {:error, stddev_error} = Volatility.standard_deviation(short_data, period: 5)
      {:error, atr_error} = Volatility.atr(short_data, period: 5)
      {:error, bb_error} = Volatility.bollinger_bands(short_data, period: 5)
      {:error, vol_error} = Volatility.volatility_index(short_data, period: 5)

      # All should be InsufficientData errors
      assert %Errors.InsufficientData{} = stddev_error
      assert %Errors.InsufficientData{} = atr_error
      assert %Errors.InsufficientData{} = bb_error
      assert %Errors.InsufficientData{} = vol_error
    end
  end
end
