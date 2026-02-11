defmodule TradingIndicators.Volatility.StandardDeviationTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Volatility.StandardDeviation

  alias TradingIndicators.Volatility.StandardDeviation
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
    test "calculates standard deviation with default parameters" do
      data = Enum.take(@sample_ohlcv_data, 4)
      {:ok, results} = StandardDeviation.calculate(data, period: 3)

      assert length(results) == 2
      assert [first, second] = results

      # Check structure
      assert %{value: value1, timestamp: timestamp1, metadata: metadata1} = first
      assert Decimal.is_decimal(value1)
      assert %DateTime{} = timestamp1
      assert metadata1.indicator == "STDDEV"
      assert metadata1.period == 3

      # Values should be positive
      assert Decimal.positive?(value1)
      assert Decimal.positive?(second.value)
    end

    test "calculates with sample standard deviation (default)" do
      {:ok, results} = StandardDeviation.calculate(@sample_price_series, period: 3)

      assert length(results) == 4
      first_result = List.first(results)
      assert first_result.metadata.calculation == :sample

      # Sample std dev should use N-1 denominator
      # Manually verify first calculation: [100, 102, 104]
      # Mean = 102, variance = ((100-102)² + (102-102)² + (104-102)²) / (3-1) = 8/2 = 4
      # StdDev = sqrt(4) = 2
      expected = Decimal.new("2.0")
      assert Decimal.eq?(Decimal.round(first_result.value, 1), expected)
    end

    test "calculates with population standard deviation" do
      {:ok, sample_results} =
        StandardDeviation.calculate(@sample_price_series, period: 3, calculation: :sample)

      {:ok, pop_results} =
        StandardDeviation.calculate(@sample_price_series, period: 3, calculation: :population)

      assert length(sample_results) == length(pop_results)

      # Population std dev should be smaller than sample std dev (uses N instead of N-1)
      first_sample = List.first(sample_results).value
      first_pop = List.first(pop_results).value

      assert Decimal.lt?(first_pop, first_sample)
      assert List.first(pop_results).metadata.calculation == :population
    end

    test "calculates with different price sources" do
      {:ok, close_results} =
        StandardDeviation.calculate(@sample_ohlcv_data, period: 3, source: :close)

      {:ok, high_results} =
        StandardDeviation.calculate(@sample_ohlcv_data, period: 3, source: :high)

      {:ok, low_results} = StandardDeviation.calculate(@sample_ohlcv_data, period: 3, source: :low)

      # Should have same number of results
      assert length(close_results) == length(high_results)
      assert length(high_results) == length(low_results)

      # Verify that results use different price sources
      assert List.first(close_results).metadata.source == :close
      assert List.first(high_results).metadata.source == :high

      # Values may or may not be different depending on the data
      # The important thing is that they are calculated from different sources
    end

    test "works with price series (list of decimals)" do
      {:ok, results} = StandardDeviation.calculate(@sample_price_series, period: 4)

      assert length(results) == 3

      assert Enum.all?(results, fn result ->
               Decimal.is_decimal(result.value) and Decimal.positive?(result.value)
             end)
    end

    test "returns error for insufficient data" do
      short_data = Enum.take(@sample_ohlcv_data, 2)
      {:error, error} = StandardDeviation.calculate(short_data, period: 5)

      assert %Errors.InsufficientData{} = error
      assert error.required == 5
      assert error.provided == 2
    end

    test "returns error for invalid period" do
      {:error, error} = StandardDeviation.calculate(@sample_ohlcv_data, period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = StandardDeviation.calculate(@sample_ohlcv_data, period: -1)
      assert %Errors.InvalidParams{param: :period} = error
    end

    test "returns error for invalid calculation type" do
      {:error, error} =
        StandardDeviation.calculate(@sample_ohlcv_data, period: 3, calculation: :invalid)

      assert %Errors.InvalidParams{param: :calculation} = error
    end

    test "returns error for invalid source" do
      {:error, error} = StandardDeviation.calculate(@sample_ohlcv_data, period: 3, source: :invalid)
      assert %Errors.InvalidParams{param: :source} = error
    end
  end

  describe "validate_params/1" do
    test "validates correct parameters" do
      assert :ok = StandardDeviation.validate_params(period: 20)
      assert :ok = StandardDeviation.validate_params(period: 10, source: :high)
      assert :ok = StandardDeviation.validate_params(period: 5, calculation: :population)
    end

    test "rejects invalid parameters" do
      {:error, error} = StandardDeviation.validate_params(period: 1)
      assert %Errors.InvalidParams{param: :period} = error

      {:error, error} = StandardDeviation.validate_params(source: :invalid)
      assert %Errors.InvalidParams{param: :source} = error

      {:error, error} = StandardDeviation.validate_params(calculation: :invalid)
      assert %Errors.InvalidParams{param: :calculation} = error
    end

    test "rejects non-keyword list" do
      {:error, error} = StandardDeviation.validate_params("not a keyword list")
      assert %Errors.InvalidParams{param: :opts} = error
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default required periods" do
      assert StandardDeviation.required_periods() == 20
    end

    test "returns configured required periods" do
      assert StandardDeviation.required_periods(period: 14) == 14
      assert StandardDeviation.required_periods(period: 30) == 30
    end
  end

  describe "streaming support" do
    test "init_state/1 creates initial state" do
      state = StandardDeviation.init_state(period: 5, calculation: :sample)

      assert %{period: 5, source: :close, calculation: :sample, prices: [], count: 0} = state
    end

    test "update_state/2 processes data points correctly" do
      state = StandardDeviation.init_state(period: 3)

      # Add first data point - should not return result yet
      data_point1 = List.first(@sample_ohlcv_data)
      {:ok, new_state1, nil} = StandardDeviation.update_state(state, data_point1)
      assert new_state1.count == 1
      assert length(new_state1.prices) == 1

      # Add second data point - still not enough
      data_point2 = Enum.at(@sample_ohlcv_data, 1)
      {:ok, new_state2, nil} = StandardDeviation.update_state(new_state1, data_point2)
      assert new_state2.count == 2

      # Add third data point - should return first result
      data_point3 = Enum.at(@sample_ohlcv_data, 2)
      {:ok, new_state3, result} = StandardDeviation.update_state(new_state2, data_point3)

      assert new_state3.count == 3
      assert %{value: value, timestamp: timestamp, metadata: metadata} = result
      assert Decimal.is_decimal(value)
      assert %DateTime{} = timestamp
      assert metadata.indicator == "STDDEV"
    end

    test "update_state/2 maintains rolling window" do
      state = StandardDeviation.init_state(period: 2)

      # Fill initial window
      {:ok, state, _} = StandardDeviation.update_state(state, List.first(@sample_ohlcv_data))
      {:ok, state, result1} = StandardDeviation.update_state(state, Enum.at(@sample_ohlcv_data, 1))

      assert length(state.prices) == 2
      assert result1 != nil

      # Add another point - should maintain window size of 2
      {:ok, state, result2} = StandardDeviation.update_state(state, Enum.at(@sample_ohlcv_data, 2))

      assert length(state.prices) == 2
      assert result2 != nil
      # Values should be different
      refute Decimal.eq?(result1.value, result2.value)
    end

    test "update_state/2 works with decimal prices" do
      state = StandardDeviation.init_state(period: 2)

      # Test with decimal price directly
      {:ok, new_state, nil} = StandardDeviation.update_state(state, Decimal.new("100.0"))
      {:ok, _final_state, result} = StandardDeviation.update_state(new_state, Decimal.new("102.0"))

      assert %{value: value} = result
      assert Decimal.is_decimal(value)
      assert Decimal.positive?(value)
    end

    test "update_state/2 handles invalid state" do
      {:error, error} = StandardDeviation.update_state(%{invalid: :state}, Decimal.new("100"))
      assert %Errors.StreamStateError{} = error
    end
  end

  describe "edge cases" do
    test "handles identical values (zero standard deviation)" do
      identical_data = [
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("100.0"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]

      {:ok, results} = StandardDeviation.calculate(identical_data, period: 3)

      assert length(results) == 1
      result = List.first(results)
      assert Decimal.eq?(result.value, Decimal.new("0.0"))
    end

    test "handles minimum period of 2" do
      data = Enum.take(@sample_ohlcv_data, 2)
      {:ok, results} = StandardDeviation.calculate(data, period: 2)

      assert length(results) == 1
      assert Decimal.positive?(List.first(results).value)
    end

    test "precision is maintained" do
      {:ok, results} = StandardDeviation.calculate(@sample_price_series, period: 3)

      # Check that results have expected precision (6 decimal places)
      result_value = List.first(results).value

      decimal_places =
        result_value |> Decimal.to_string() |> String.split(".") |> List.last() |> String.length()

      assert decimal_places <= 6
    end

    test "handles large datasets efficiently" do
      large_data =
        for _i <- 1..1000 do
          %{close: Decimal.new(100 + :rand.uniform(20)), timestamp: DateTime.utc_now()}
        end

      {:ok, results} = StandardDeviation.calculate(large_data, period: 50)

      # 1000 - 50 + 1
      assert length(results) == 951
      assert Enum.all?(results, &Decimal.positive?(&1.value))
    end
  end

  describe "mathematical accuracy" do
    test "matches known standard deviation calculation" do
      # Test with simple dataset where we can verify manually
      simple_data = [
        Decimal.new("2.0"),
        Decimal.new("4.0"),
        Decimal.new("4.0"),
        Decimal.new("4.0"),
        Decimal.new("5.0"),
        Decimal.new("5.0"),
        Decimal.new("7.0"),
        Decimal.new("9.0")
      ]

      {:ok, results} = StandardDeviation.calculate(simple_data, period: 8, calculation: :population)

      # Population std dev for this dataset should be exactly 2.0
      result = List.first(results)
      expected = Decimal.new("2.0")
      assert Decimal.eq?(Decimal.round(result.value, 1), expected)
    end

    test "population vs sample calculation difference" do
      data = [Decimal.new("1"), Decimal.new("2"), Decimal.new("3")]

      {:ok, sample_results} = StandardDeviation.calculate(data, period: 3, calculation: :sample)
      {:ok, pop_results} = StandardDeviation.calculate(data, period: 3, calculation: :population)

      sample_val = List.first(sample_results).value
      pop_val = List.first(pop_results).value

      # Sample std dev should be larger than population std dev
      assert Decimal.gt?(sample_val, pop_val)

      # The ratio should be sqrt(n/(n-1)) = sqrt(3/2) ≈ 1.225
      ratio = Decimal.div(sample_val, pop_val)
      expected_ratio = Decimal.from_float(:math.sqrt(3 / 2))
      assert Decimal.eq?(Decimal.round(ratio, 3), Decimal.round(expected_ratio, 3))
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = StandardDeviation.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = StandardDeviation.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
