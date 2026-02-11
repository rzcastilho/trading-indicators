defmodule TradingIndicators.Volatility.BollingerBandsTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Volatility.BollingerBands

  alias TradingIndicators.Volatility.BollingerBands
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

  describe "calculate/2" do
    test "calculates Bollinger Bands with default parameters" do
      data = Enum.take(@sample_ohlcv_data, 4)
      {:ok, results} = BollingerBands.calculate(data, period: 3)

      assert length(results) == 2
      [first, _second] = results

      # Check structure
      assert %{
               upper_band: upper1,
               middle_band: middle1,
               lower_band: lower1,
               percent_b: percent_b1,
               bandwidth: bandwidth1,
               timestamp: timestamp1,
               metadata: metadata1
             } = first

      assert Decimal.is_decimal(upper1)
      assert Decimal.is_decimal(middle1)
      assert Decimal.is_decimal(lower1)
      assert Decimal.is_decimal(percent_b1)
      assert Decimal.is_decimal(bandwidth1)
      assert %DateTime{} = timestamp1
      assert metadata1.indicator == "BOLLINGER"
      assert metadata1.period == 3
      assert metadata1.multiplier == Decimal.new("2.0")

      # Band relationships
      assert Decimal.gt?(upper1, middle1)
      assert Decimal.gt?(middle1, lower1)
      assert Decimal.positive?(bandwidth1)
    end

    test "calculates with custom multiplier" do
      {:ok, results_2x} = BollingerBands.calculate(@sample_price_series, period: 3, multiplier: 2.0)
      {:ok, results_1x} = BollingerBands.calculate(@sample_price_series, period: 3, multiplier: 1.0)

      assert length(results_2x) == length(results_1x)

      # 2x multiplier should create wider bands
      first_2x = List.first(results_2x)
      first_1x = List.first(results_1x)

      band_width_2x = Decimal.sub(first_2x.upper_band, first_2x.lower_band)
      band_width_1x = Decimal.sub(first_1x.upper_band, first_1x.lower_band)

      assert Decimal.gt?(band_width_2x, band_width_1x)

      # Middle bands should be the same (SMA doesn't change)
      assert Decimal.eq?(first_2x.middle_band, first_1x.middle_band)
    end

    test "calculates with different price sources" do
      {:ok, close_results} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, source: :close)
      {:ok, high_results} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, source: :high)
      {:ok, low_results} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, source: :low)

      # Should have same number of results
      assert length(close_results) == length(high_results)
      assert length(high_results) == length(low_results)

      # Middle bands should generally be different
      close_first = List.first(close_results)
      high_first = List.first(high_results)

      refute Decimal.eq?(close_first.middle_band, high_first.middle_band)
    end

    test "works with price series (list of decimals)" do
      {:ok, results} = BollingerBands.calculate(@sample_price_series, period: 4)

      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               Decimal.gt?(result.upper_band, result.middle_band) and
                 Decimal.gt?(result.middle_band, result.lower_band)
             end)
    end

    test "returns error for insufficient data" do
      short_data = Enum.take(@sample_ohlcv_data, 2)
      {:error, error} = BollingerBands.calculate(short_data, period: 5)

      assert %Errors.InsufficientData{} = error
      assert error.required == 5
      assert error.provided == 2
    end

    test "returns error for invalid period" do
      {:error, error} = BollingerBands.calculate(@sample_ohlcv_data, period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = BollingerBands.calculate(@sample_ohlcv_data, period: -1)
      assert %Errors.InvalidParams{param: :period} = error
    end

    test "returns error for invalid multiplier" do
      {:error, error} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, multiplier: 0)
      assert %Errors.InvalidParams{param: :multiplier} = error

      {:error, error} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, multiplier: -1)
      assert %Errors.InvalidParams{param: :multiplier} = error
    end

    test "returns error for invalid source" do
      {:error, error} = BollingerBands.calculate(@sample_ohlcv_data, period: 3, source: :invalid)
      assert %Errors.InvalidParams{param: :source} = error
    end
  end

  describe "validate_params/1" do
    test "validates correct parameters" do
      assert :ok = BollingerBands.validate_params(period: 20)
      assert :ok = BollingerBands.validate_params(period: 10, multiplier: 2.5)

      assert :ok =
               BollingerBands.validate_params(
                 period: 5,
                 source: :high,
                 multiplier: Decimal.new("1.5")
               )
    end

    test "rejects invalid parameters" do
      {:error, error} = BollingerBands.validate_params(period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = BollingerBands.validate_params(multiplier: 0)
      assert %Errors.InvalidParams{param: :multiplier} = error

      {:error, error} = BollingerBands.validate_params(source: :invalid)
      assert %Errors.InvalidParams{param: :source} = error
    end

    test "rejects non-keyword list" do
      {:error, error} = BollingerBands.validate_params("not a keyword list")
      assert %Errors.InvalidParams{param: :opts} = error
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default required periods" do
      assert BollingerBands.required_periods() == 20
    end

    test "returns configured required periods" do
      assert BollingerBands.required_periods(period: 14) == 14
      assert BollingerBands.required_periods(period: 30) == 30
    end
  end

  describe "streaming support" do
    test "init_state/1 creates initial state" do
      state = BollingerBands.init_state(period: 5, multiplier: 2.5)

      assert %{
               period: 5,
               multiplier: multiplier,
               source: :close,
               prices: [],
               count: 0
             } = state

      assert Decimal.eq?(multiplier, Decimal.new("2.5"))
    end

    test "update_state/2 processes data points correctly" do
      state = BollingerBands.init_state(period: 3)

      # Add first data point - should not return result yet
      data_point1 = List.first(@sample_ohlcv_data)
      {:ok, new_state1, nil} = BollingerBands.update_state(state, data_point1)
      assert new_state1.count == 1
      assert length(new_state1.prices) == 1

      # Add second data point - still not enough
      data_point2 = Enum.at(@sample_ohlcv_data, 1)
      {:ok, new_state2, nil} = BollingerBands.update_state(new_state1, data_point2)
      assert new_state2.count == 2

      # Add third data point - should return first result
      data_point3 = Enum.at(@sample_ohlcv_data, 2)
      {:ok, new_state3, result} = BollingerBands.update_state(new_state2, data_point3)

      assert new_state3.count == 3

      assert %{
               upper_band: upper,
               middle_band: middle,
               lower_band: lower,
               percent_b: percent_b,
               bandwidth: bandwidth,
               timestamp: timestamp,
               metadata: metadata
             } = result

      assert Decimal.is_decimal(upper)
      assert Decimal.is_decimal(middle)
      assert Decimal.is_decimal(lower)
      assert Decimal.is_decimal(percent_b)
      assert Decimal.is_decimal(bandwidth)
      assert %DateTime{} = timestamp
      assert metadata.indicator == "BOLLINGER"
    end

    test "update_state/2 maintains rolling window" do
      state = BollingerBands.init_state(period: 2)

      # Fill initial window
      {:ok, state, _} = BollingerBands.update_state(state, List.first(@sample_ohlcv_data))
      {:ok, state, result1} = BollingerBands.update_state(state, Enum.at(@sample_ohlcv_data, 1))

      assert length(state.prices) == 2
      assert result1 != nil

      # Add another point - should maintain window size of 2
      {:ok, state, result2} = BollingerBands.update_state(state, Enum.at(@sample_ohlcv_data, 2))

      assert length(state.prices) == 2
      assert result2 != nil
      # Values should be different
      refute Decimal.eq?(result1.middle_band, result2.middle_band)
    end

    test "update_state/2 works with decimal prices" do
      state = BollingerBands.init_state(period: 2)

      # Test with decimal price directly
      {:ok, new_state, nil} = BollingerBands.update_state(state, Decimal.new("100.0"))
      {:ok, _final_state, result} = BollingerBands.update_state(new_state, Decimal.new("102.0"))

      assert %{upper_band: upper, middle_band: middle, lower_band: lower} = result
      assert Decimal.is_decimal(upper)
      assert Decimal.is_decimal(middle)
      assert Decimal.is_decimal(lower)
    end

    test "update_state/2 handles invalid state" do
      {:error, error} = BollingerBands.update_state(%{invalid: :state}, Decimal.new("100"))
      assert %Errors.StreamStateError{} = error
    end
  end

  describe "%B and Bandwidth calculations" do
    test "calculates %B correctly" do
      # Test with known prices where we can verify %B calculation
      test_data = [
        Decimal.new("90.0"),
        Decimal.new("100.0"),
        Decimal.new("110.0")
      ]

      {:ok, results} = BollingerBands.calculate(test_data, period: 3, multiplier: 1.0)
      result = List.first(results)

      # With multiplier 1.0, middle = 100, std_dev = sqrt(200/2) ≈ 10
      # Upper band = 100 + 10 = 110, Lower band = 100 - 10 = 90
      # Current price = 110, so %B = (110 - 90) / (110 - 90) * 100 = 100%
      assert Decimal.eq?(Decimal.round(result.percent_b, 0), Decimal.new("100"))
    end

    test "calculates bandwidth correctly" do
      # Test bandwidth calculation
      test_data = [
        Decimal.new("95.0"),
        Decimal.new("100.0"),
        Decimal.new("105.0")
      ]

      {:ok, results} = BollingerBands.calculate(test_data, period: 3, multiplier: 1.0)
      result = List.first(results)

      # Middle = 100, std_dev ≈ 5, bands are 95 and 105
      # Bandwidth = (105 - 95) / 100 * 100 = 10%
      expected_bandwidth = Decimal.new("10.0")
      assert Decimal.eq?(Decimal.round(result.bandwidth, 0), expected_bandwidth)
    end

    test "%B indicates price position relative to bands" do
      # Test %B with price at different positions
      test_data = [
        # Price below middle
        Decimal.new("90.0"),
        Decimal.new("100.0"),
        Decimal.new("92.0")
      ]

      {:ok, results} = BollingerBands.calculate(test_data, period: 3, multiplier: 1.0)
      result = List.first(results)

      # Price at 92 should have %B < 50 (below middle band)
      assert Decimal.lt?(result.percent_b, Decimal.new("50.0"))
    end
  end

  describe "edge cases" do
    test "handles identical values (zero standard deviation)" do
      identical_data = [
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = BollingerBands.calculate(identical_data, period: 3)
      result = List.first(results)

      # All bands should be equal when std dev is 0
      assert Decimal.eq?(result.upper_band, result.middle_band)
      assert Decimal.eq?(result.middle_band, result.lower_band)

      # %B should be 50% when bands collapse
      assert Decimal.eq?(result.percent_b, Decimal.new("50.0"))

      # Bandwidth should be 0
      assert Decimal.eq?(result.bandwidth, Decimal.new("0.0"))
    end

    test "handles minimum period of 2" do
      data = Enum.take(@sample_ohlcv_data, 2)
      {:ok, results} = BollingerBands.calculate(data, period: 2)

      assert length(results) == 1
      result = List.first(results)
      assert Decimal.gt?(result.upper_band, result.middle_band)
      assert Decimal.gt?(result.middle_band, result.lower_band)
    end

    test "handles large datasets efficiently" do
      large_data =
        for _i <- 1..500 do
          %{close: Decimal.new(100 + :rand.uniform(20) - 10), timestamp: DateTime.utc_now()}
        end

      {:ok, results} = BollingerBands.calculate(large_data, period: 20)

      # 500 - 20 + 1
      assert length(results) == 481

      assert Enum.all?(results, fn result ->
               Decimal.gt?(result.upper_band, result.lower_band) and
                 Decimal.positive?(result.bandwidth)
             end)
    end

    test "handles zero middle band (division by zero protection)" do
      # This is an edge case that shouldn't happen in practice, but we test the protection
      zero_data = [
        %{close: Decimal.new("0.0"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.0"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      {:ok, results} = BollingerBands.calculate(zero_data, period: 2)
      result = List.first(results)

      # Should handle division by zero gracefully
      assert Decimal.eq?(result.bandwidth, Decimal.new("0.0"))
    end
  end

  describe "mathematical accuracy" do
    test "middle band equals SMA" do
      # Verify that middle band is exactly the SMA
      test_data = [
        Decimal.new("10.0"),
        Decimal.new("20.0"),
        Decimal.new("30.0")
      ]

      {:ok, results} = BollingerBands.calculate(test_data, period: 3)
      result = List.first(results)

      # SMA should be (10 + 20 + 30) / 3 = 20
      expected_sma = Decimal.new("20.0")
      assert Decimal.eq?(result.middle_band, expected_sma)
    end

    test "band distances are symmetric with standard multiplier" do
      {:ok, results} = BollingerBands.calculate(@sample_price_series, period: 3, multiplier: 2.0)
      result = List.first(results)

      upper_distance = Decimal.sub(result.upper_band, result.middle_band)
      lower_distance = Decimal.sub(result.middle_band, result.lower_band)

      # Distances should be equal (symmetric around middle band)
      assert Decimal.eq?(Decimal.round(upper_distance, 6), Decimal.round(lower_distance, 6))
    end

    test "multiplier scaling works correctly" do
      {:ok, results_1x} = BollingerBands.calculate(@sample_price_series, period: 3, multiplier: 1.0)
      {:ok, results_2x} = BollingerBands.calculate(@sample_price_series, period: 3, multiplier: 2.0)

      result_1x = List.first(results_1x)
      result_2x = List.first(results_2x)

      distance_1x = Decimal.sub(result_1x.upper_band, result_1x.middle_band)
      distance_2x = Decimal.sub(result_2x.upper_band, result_2x.middle_band)

      # 2x multiplier should create exactly 2x the distance
      expected_distance_2x = Decimal.mult(distance_1x, Decimal.new("2.0"))
      assert Decimal.eq?(Decimal.round(distance_2x, 6), Decimal.round(expected_distance_2x, 6))
    end
  end

  describe "parameter_metadata/0" do
    test "returns correct parameter metadata" do
      metadata = BollingerBands.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 3

      # Verify period parameter
      period_param = Enum.find(metadata, fn p -> p.name == :period end)
      assert period_param != nil
      assert period_param.type == :integer
      assert period_param.default == 20
      assert period_param.required == false
      assert period_param.min == 2
      assert period_param.max == nil
      assert period_param.options == nil
      assert period_param.description == "Number of periods for SMA and Standard Deviation"

      # Verify multiplier parameter
      multiplier_param = Enum.find(metadata, fn p -> p.name == :multiplier end)
      assert multiplier_param != nil
      assert multiplier_param.type == :float
      assert multiplier_param.default == 2.0
      assert multiplier_param.required == false
      assert multiplier_param.min == 0.0
      assert multiplier_param.max == nil
      assert multiplier_param.description == "Standard deviation multiplier for bands"

      # Verify source parameter
      source_param = Enum.find(metadata, fn p -> p.name == :source end)
      assert source_param != nil
      assert source_param.type == :atom
      assert source_param.default == :close
      assert source_param.options == [:open, :high, :low, :close]
    end

    test "all metadata maps have required fields" do
      metadata = BollingerBands.parameter_metadata()

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
    test "returns correct metadata for multi-value indicator" do
      metadata = BollingerBands.output_fields_metadata()

      assert metadata.type == :multi_value
      assert is_list(metadata.fields)
      assert length(metadata.fields) > 0

      # Verify each field has required attributes
      for field <- metadata.fields do
        assert is_atom(field.name)
        assert field.type in [:decimal, :integer, :map]
        assert is_binary(field.description)
      end
    end

    test "metadata has all required fields" do
      metadata = BollingerBands.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :fields)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
    end
  end
end
