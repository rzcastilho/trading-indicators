defmodule TradingIndicators.Volatility.VolatilityIndexTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Volatility.VolatilityIndex

  alias TradingIndicators.Volatility.VolatilityIndex
  alias TradingIndicators.Errors
  require Decimal

  @sample_ohlc_data [
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
    test "calculates historical volatility with default parameters" do
      {:ok, results} = VolatilityIndex.calculate(@sample_price_series, period: 3)

      # 6 - 3 - 1 + 1 (need extra for returns)
      assert length(results) == 3
      [first, second, third] = results

      # Check structure
      assert %{value: value1, timestamp: timestamp1, metadata: metadata1} = first
      assert Decimal.is_decimal(value1)
      assert %DateTime{} = timestamp1
      assert metadata1.indicator == "VOLATILITY"
      assert metadata1.period == 3
      assert metadata1.method == :historical
      assert metadata1.periods_per_year == 252

      # Values should be positive (volatility is always positive)
      assert Decimal.positive?(value1)
      assert Decimal.positive?(second.value)
      assert Decimal.positive?(third.value)
    end

    test "calculates Garman-Klass volatility" do
      {:ok, results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :garman_klass)

      assert length(results) == 3
      first_result = List.first(results)
      assert first_result.metadata.method == :garman_klass
      assert Decimal.positive?(first_result.value)
    end

    test "calculates Parkinson volatility" do
      {:ok, results} = VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :parkinson)

      assert length(results) == 3
      first_result = List.first(results)
      assert first_result.metadata.method == :parkinson
      assert Decimal.positive?(first_result.value)
    end

    test "different methods produce different results" do
      {:ok, historical_results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :historical)

      {:ok, gk_results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :garman_klass)

      {:ok, parkinson_results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :parkinson)

      # Historical method produces fewer results due to returns calculation
      # But all should have at least one result for comparison
      assert length(historical_results) >= 1
      assert length(gk_results) >= 1
      assert length(parkinson_results) >= 1

      # GK and Parkinson should have same length (both use raw OHLC)
      assert length(gk_results) == length(parkinson_results)

      # Values should generally be different
      hist_val = List.first(historical_results).value
      gk_val = List.first(gk_results).value
      park_val = List.first(parkinson_results).value

      # At least two should be different
      unique_values = [hist_val, gk_val, park_val] |> Enum.uniq() |> length()
      assert unique_values >= 2
    end

    test "calculates with custom periods per year" do
      {:ok, daily_results} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, periods_per_year: 252)

      {:ok, hourly_results} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, periods_per_year: 8760)

      assert length(daily_results) == length(hourly_results)

      # Hourly annualization should produce higher volatility values
      daily_val = List.first(daily_results).value
      hourly_val = List.first(hourly_results).value

      assert Decimal.gt?(hourly_val, daily_val)
    end

    test "calculates with different price sources for historical method" do
      {:ok, close_results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :historical, source: :close)

      {:ok, high_results} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :historical, source: :high)

      # Should have same number of results
      assert length(close_results) == length(high_results)

      # Values should generally be different
      close_first = List.first(close_results).value
      high_first = List.first(high_results).value

      refute Decimal.eq?(close_first, high_first)
    end

    test "works with price series for historical method" do
      {:ok, results} =
        VolatilityIndex.calculate(@sample_price_series, period: 4, method: :historical)

      # 6 - 4 - 1 + 1
      assert length(results) == 2
      assert Enum.all?(results, &Decimal.positive?(&1.value))
    end

    test "returns error for insufficient data" do
      short_data = Enum.take(@sample_ohlc_data, 2)
      {:error, error} = VolatilityIndex.calculate(short_data, period: 5)

      assert %Errors.InsufficientData{} = error
      # period + 1
      assert error.required == 6
      assert error.provided == 2
    end

    test "returns error for invalid period" do
      {:error, error} = VolatilityIndex.calculate(@sample_ohlc_data, period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = VolatilityIndex.calculate(@sample_ohlc_data, period: -1)
      assert %Errors.InvalidParams{param: :period} = error
    end

    test "returns error for invalid method" do
      {:error, error} = VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :invalid)
      assert %Errors.InvalidParams{param: :method} = error
    end

    test "returns error for invalid periods per year" do
      {:error, error} = VolatilityIndex.calculate(@sample_ohlc_data, period: 3, periods_per_year: 0)
      assert %Errors.InvalidParams{param: :periods_per_year} = error

      {:error, error} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, periods_per_year: -1)

      assert %Errors.InvalidParams{param: :periods_per_year} = error
    end

    test "returns error when using Garman-Klass with price series" do
      {:error, error} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, method: :garman_klass)

      assert %Errors.InvalidDataFormat{} = error
    end

    test "returns error when using Parkinson with price series" do
      {:error, error} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, method: :parkinson)

      assert %Errors.InvalidDataFormat{} = error
    end
  end

  describe "validate_params/1" do
    test "validates correct parameters" do
      assert :ok = VolatilityIndex.validate_params(period: 20)
      assert :ok = VolatilityIndex.validate_params(period: 10, method: :historical)

      assert :ok =
               VolatilityIndex.validate_params(
                 period: 5,
                 method: :garman_klass,
                 periods_per_year: 365
               )
    end

    test "rejects invalid parameters" do
      {:error, error} = VolatilityIndex.validate_params(period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = VolatilityIndex.validate_params(method: :invalid)
      assert %Errors.InvalidParams{param: :method} = error

      {:error, error} = VolatilityIndex.validate_params(periods_per_year: 0)
      assert %Errors.InvalidParams{param: :periods_per_year} = error

      {:error, error} = VolatilityIndex.validate_params(source: :invalid)
      assert %Errors.InvalidParams{param: :source} = error
    end

    test "rejects non-keyword list" do
      {:error, error} = VolatilityIndex.validate_params("not a keyword list")
      assert %Errors.InvalidParams{param: :opts} = error
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default required periods" do
      # 20 + 1
      assert VolatilityIndex.required_periods() == 21
    end

    test "returns configured required periods" do
      # 14 + 1
      assert VolatilityIndex.required_periods(period: 14) == 15
      # 30 + 1
      assert VolatilityIndex.required_periods(period: 30) == 31
    end
  end

  describe "streaming support" do
    test "init_state/1 creates initial state" do
      state = VolatilityIndex.init_state(period: 5, method: :historical, periods_per_year: 365)

      assert %{
               period: 5,
               method: :historical,
               periods_per_year: 365,
               source: :close,
               data_points: [],
               count: 0
             } = state
    end

    test "update_state/2 processes data points correctly for historical method" do
      state = VolatilityIndex.init_state(period: 3, method: :historical)

      # Add data points - need period + 1 for historical method
      {:ok, state, nil} = VolatilityIndex.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, nil} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 1))
      {:ok, state, nil} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 2))

      assert state.count == 3
      assert length(state.data_points) == 3

      # Add fourth data point - should return first result
      {:ok, new_state, result} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 3))

      assert new_state.count == 4
      assert %{value: value, timestamp: timestamp, metadata: metadata} = result
      assert Decimal.is_decimal(value)
      assert Decimal.positive?(value)
      assert %DateTime{} = timestamp
      assert metadata.indicator == "VOLATILITY"
      assert metadata.method == :historical
    end

    test "update_state/2 processes data points correctly for Garman-Klass method" do
      state = VolatilityIndex.init_state(period: 2, method: :garman_klass)

      # Add minimum required data points
      {:ok, state, nil} = VolatilityIndex.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, nil} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 1))

      # Add third data point - should return first result
      {:ok, _new_state, result} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 2))

      assert result != nil
      assert result.metadata.method == :garman_klass
      assert Decimal.positive?(result.value)
    end

    test "update_state/2 maintains rolling window" do
      state = VolatilityIndex.init_state(period: 2, method: :historical)

      # Fill initial window (need 3 points for period 2)
      {:ok, state, _} = VolatilityIndex.update_state(state, List.first(@sample_ohlc_data))
      {:ok, state, _} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 1))
      {:ok, state, result1} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 2))

      # period + 1
      assert length(state.data_points) == 3
      assert result1 != nil

      # Add another point - should maintain window size
      {:ok, state, result2} = VolatilityIndex.update_state(state, Enum.at(@sample_ohlc_data, 3))

      # period + 1
      assert length(state.data_points) == 3
      assert result2 != nil
      # Values should be different
      refute Decimal.eq?(result1.value, result2.value)
    end

    test "update_state/2 works with decimal prices for historical method" do
      state = VolatilityIndex.init_state(period: 2, method: :historical)

      # Test with decimal price directly
      {:ok, state, nil} = VolatilityIndex.update_state(state, Decimal.new("100.0"))
      {:ok, state, nil} = VolatilityIndex.update_state(state, Decimal.new("102.0"))
      {:ok, _state, result} = VolatilityIndex.update_state(state, Decimal.new("104.0"))

      assert %{value: value} = result
      assert Decimal.is_decimal(value)
      assert Decimal.positive?(value)
    end

    test "update_state/2 handles invalid state" do
      {:error, error} =
        VolatilityIndex.update_state(%{invalid: :state}, List.first(@sample_ohlc_data))

      assert %Errors.StreamStateError{} = error
    end
  end

  describe "edge cases" do
    test "handles identical values (zero volatility)" do
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
        },
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("100.0"),
          low: Decimal.new("100.0"),
          close: Decimal.new("100.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = VolatilityIndex.calculate(identical_data, period: 2, method: :historical)

      # Should handle zero volatility case
      assert length(results) == 1
      result = List.first(results)
      assert Decimal.eq?(result.value, Decimal.new("0.0"))
    end

    test "handles minimum period of 2" do
      # Need 3 points for period 2
      data = Enum.take(@sample_ohlc_data, 3)
      {:ok, results} = VolatilityIndex.calculate(data, period: 2, method: :historical)

      assert length(results) == 1
      assert Decimal.positive?(List.first(results).value)
    end

    test "handles large datasets efficiently" do
      large_data =
        for _i <- 1..300 do
          base_price = 100.0
          variation = (:rand.uniform(20) - 10) / 10.0
          price = base_price + variation

          %{
            open: Decimal.from_float(price),
            high: Decimal.from_float(price + 1),
            low: Decimal.from_float(price - 1),
            close: Decimal.from_float(price + variation / 2),
            volume: 1000,
            timestamp: DateTime.utc_now()
          }
        end

      {:ok, results} = VolatilityIndex.calculate(large_data, period: 20, method: :historical)

      # 300 - 20 - 1 + 1
      assert length(results) == 280
      assert Enum.all?(results, &Decimal.positive?(&1.value))
    end
  end

  describe "mathematical accuracy" do
    test "historical volatility calculation accuracy" do
      # Test with known data where we can verify calculation
      simple_data = [
        Decimal.new("100.0"),
        Decimal.new("110.0"),
        Decimal.new("90.0")
      ]

      {:ok, results} =
        VolatilityIndex.calculate(simple_data, period: 2, method: :historical, periods_per_year: 1)

      result = List.first(results)

      # With periods_per_year = 1, we should get standard deviation of log returns
      # Log returns: ln(110/100) ≈ 0.0953, ln(90/110) ≈ -0.2007
      # Standard deviation ≈ 0.2097, annualized (×1) = 0.2097, as percentage = 20.97%
      assert Decimal.gt?(result.value, Decimal.new("20.0"))
      assert Decimal.lt?(result.value, Decimal.new("25.0"))
    end

    test "Garman-Klass estimator produces reasonable values" do
      # GK typically produces higher volatility estimates than historical
      {:ok, historical} =
        VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :historical)

      {:ok, gk} = VolatilityIndex.calculate(@sample_ohlc_data, period: 3, method: :garman_klass)

      hist_val = List.first(historical).value
      gk_val = List.first(gk).value

      # Both should be positive
      assert Decimal.positive?(hist_val)
      assert Decimal.positive?(gk_val)

      # GK often produces higher estimates due to intraday information
      # This isn't always true, but they should at least be in similar magnitude
      ratio = Decimal.div(gk_val, hist_val)
      # Within order of magnitude
      assert Decimal.gt?(ratio, Decimal.new("0.1"))
      # Within order of magnitude
      assert Decimal.lt?(ratio, Decimal.new("10.0"))
    end

    test "Parkinson estimator uses high-low range" do
      # Test with data that has significant high-low range
      wide_range_data = [
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("120.0"),
          low: Decimal.new("80.0"),
          close: Decimal.new("110.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          open: Decimal.new("110.0"),
          high: Decimal.new("130.0"),
          low: Decimal.new("90.0"),
          close: Decimal.new("115.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:31:00Z]
        }
      ]

      {:ok, results} = VolatilityIndex.calculate(wide_range_data, period: 2, method: :parkinson)
      result = List.first(results)

      # With wide ranges, Parkinson should produce significant volatility
      assert Decimal.positive?(result.value)
      # Should be substantial
      assert Decimal.gt?(result.value, Decimal.new("50.0"))
    end

    test "annualization scaling works correctly" do
      {:ok, results_252} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, periods_per_year: 252)

      {:ok, results_1} =
        VolatilityIndex.calculate(@sample_price_series, period: 3, periods_per_year: 1)

      result_252 = List.first(results_252)
      result_1 = List.first(results_1)

      # Should scale by sqrt(252) ≈ 15.87
      expected_ratio = :math.sqrt(252)
      actual_ratio = Decimal.to_float(Decimal.div(result_252.value, result_1.value))

      # Allow for some numerical precision differences
      assert abs(actual_ratio - expected_ratio) <= 0.1
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = VolatilityIndex.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = VolatilityIndex.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
