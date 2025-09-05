defmodule TradingIndicators.UtilsTest do
  use ExUnit.Case, async: true
  require Decimal

  alias TradingIndicators.TestSupport.DataGenerator
  alias TradingIndicators.Utils

  doctest TradingIndicators.Utils

  describe "price extraction functions" do
    setup do
      data = DataGenerator.known_test_data()
      {:ok, data: data}
    end

    test "extract_closes/1 extracts closing prices", %{data: data} do
      closes = Utils.extract_closes(data)

      expected = [
        Decimal.new("103.0"),
        Decimal.new("106.0"),
        Decimal.new("105.0"),
        Decimal.new("108.0"),
        Decimal.new("107.0")
      ]

      assert closes == expected
    end

    test "extract_highs/1 extracts high prices", %{data: data} do
      highs = Utils.extract_highs(data)

      expected = [
        Decimal.new("105.0"),
        Decimal.new("107.0"),
        Decimal.new("108.0"),
        Decimal.new("109.0"),
        Decimal.new("110.0")
      ]

      assert highs == expected
    end

    test "extract_lows/1 extracts low prices", %{data: data} do
      lows = Utils.extract_lows(data)

      expected = [
        Decimal.new("99.0"),
        Decimal.new("102.0"),
        Decimal.new("104.0"),
        Decimal.new("103.0"),
        Decimal.new("106.0")
      ]

      assert lows == expected
    end

    test "extract_opens/1 extracts opening prices", %{data: data} do
      opens = Utils.extract_opens(data)

      expected = [
        Decimal.new("100.0"),
        Decimal.new("103.0"),
        Decimal.new("106.0"),
        Decimal.new("105.0"),
        Decimal.new("108.0")
      ]

      assert opens == expected
    end

    test "extract_volumes/1 extracts volume data", %{data: data} do
      volumes = Utils.extract_volumes(data)
      expected = [1000, 1200, 800, 1500, 900]

      assert volumes == expected
    end
  end

  describe "mathematical functions" do
    test "mean/1 calculates arithmetic mean" do
      assert Decimal.equal?(
               Utils.mean([
                 Decimal.new("1"),
                 Decimal.new("2"),
                 Decimal.new("3"),
                 Decimal.new("4"),
                 Decimal.new("5")
               ]),
               Decimal.new("3.0")
             )

      assert Decimal.equal?(
               Utils.mean([Decimal.new("10"), Decimal.new("20"), Decimal.new("30")]),
               Decimal.new("20.0")
             )

      assert Decimal.equal?(Utils.mean([Decimal.new("100")]), Decimal.new("100.0"))
      assert Decimal.equal?(Utils.mean([]), Decimal.new("0.0"))
    end

    test "standard_deviation/1 calculates sample standard deviation" do
      # Known values for testing
      values = [
        Decimal.new("2"),
        Decimal.new("4"),
        Decimal.new("4"),
        Decimal.new("4"),
        Decimal.new("5"),
        Decimal.new("5"),
        Decimal.new("7"),
        Decimal.new("9")
      ]

      result = Utils.standard_deviation(values)
      # Expected standard deviation is approximately 2.138
      result_float = Decimal.to_float(result)
      assert_in_delta result_float, 2.138, 0.01

      # Edge cases
      assert Decimal.equal?(Utils.standard_deviation([]), Decimal.new("0.0"))
      assert Decimal.equal?(Utils.standard_deviation([Decimal.new("5")]), Decimal.new("0.0"))

      assert Decimal.equal?(
               Utils.standard_deviation([Decimal.new("5"), Decimal.new("5"), Decimal.new("5")]),
               Decimal.new("0.0")
             )
    end

    test "variance/1 calculates sample variance" do
      values = [
        Decimal.new("2"),
        Decimal.new("4"),
        Decimal.new("4"),
        Decimal.new("4"),
        Decimal.new("5"),
        Decimal.new("5"),
        Decimal.new("7"),
        Decimal.new("9")
      ]

      result = Utils.variance(values)
      # Expected variance is approximately 4.571
      result_float = Decimal.to_float(result)
      assert_in_delta result_float, 4.571, 0.01

      # With pre-calculated mean
      mean_val = Utils.mean(values)
      result_with_mean = Utils.variance(values, mean_val)
      result_with_mean_float = Decimal.to_float(result_with_mean)
      assert_in_delta result_with_mean_float, 4.571, 0.01

      # Edge cases
      assert Decimal.equal?(Utils.variance([]), Decimal.new("0.0"))
      assert Decimal.equal?(Utils.variance([Decimal.new("5")]), Decimal.new("0.0"))
    end

    test "percentage_change/2 calculates percentage change" do
      assert Decimal.equal?(
               Utils.percentage_change(Decimal.new("100"), Decimal.new("110")),
               Decimal.new("10.0")
             )

      assert Decimal.equal?(
               Utils.percentage_change(Decimal.new("100"), Decimal.new("90")),
               Decimal.new("-10.0")
             )

      assert Decimal.equal?(
               Utils.percentage_change(Decimal.new("50"), Decimal.new("75")),
               Decimal.new("50.0")
             )

      # Edge case: division by zero
      assert Decimal.equal?(
               Utils.percentage_change(Decimal.new("0"), Decimal.new("10")),
               Decimal.new("0.0")
             )

      assert Decimal.equal?(
               Utils.percentage_change(Decimal.new("100"), Decimal.new("100")),
               Decimal.new("0.0")
             )
    end
  end

  describe "data processing functions" do
    test "sliding_window/2 creates sliding windows" do
      data = [1, 2, 3, 4, 5]

      result = Utils.sliding_window(data, 3)
      expected = [[1, 2, 3], [2, 3, 4], [3, 4, 5]]

      assert result == expected
    end

    test "sliding_window/2 handles edge cases" do
      # Window size larger than data
      assert Utils.sliding_window([1, 2], 3) == []

      # Window size equal to data size
      assert Utils.sliding_window([1, 2, 3], 3) == [[1, 2, 3]]

      # Empty data
      assert Utils.sliding_window([], 2) == []

      # Single element window
      assert Utils.sliding_window([1, 2, 3], 1) == [[1], [2], [3]]
    end

    test "validate_data_length/2 validates sufficient data" do
      data = [1, 2, 3, 4, 5]

      assert Utils.validate_data_length(data, 3) == :ok
      assert Utils.validate_data_length(data, 5) == :ok

      {:error, error} = Utils.validate_data_length(data, 10)
      assert error.required == 10
      assert error.provided == 5
      assert String.contains?(error.message, "Insufficient data")
    end
  end

  describe "financial calculations" do
    setup do
      data = DataGenerator.known_test_data()
      {:ok, data: data}
    end

    test "typical_price/1 calculates typical price for single data point", %{data: [first | _]} do
      result = Utils.typical_price(first)
      # (H + L + C) / 3
      expected =
        Decimal.div(
          Decimal.add(Decimal.add(Decimal.new("105.0"), Decimal.new("99.0")), Decimal.new("103.0")),
          Decimal.new("3.0")
        )

      assert Decimal.equal?(result, expected)
    end

    test "typical_price/1 calculates typical prices for data series", %{data: data} do
      results = Utils.typical_price(data)

      # Check first calculation: (105 + 99 + 103) / 3 = 102.333...
      first_result = Enum.at(results, 0)
      first_result_float = Decimal.to_float(first_result)
      assert_in_delta first_result_float, 102.333, 0.01

      # Check that all results are calculated
      assert length(results) == length(data)
    end

    test "true_range/2 calculates true range for single period" do
      current = %{high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0")}
      previous = %{close: Decimal.new("101.0")}

      result = Utils.true_range(current, previous)

      # Max of: (105-99), |(105-101)|, |(99-101)| = Max of: 6, 4, 2 = 6
      assert Decimal.equal?(result, Decimal.new("6.0"))
    end

    test "true_range/2 handles nil previous (first period)" do
      current = %{high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0")}

      result = Utils.true_range(current, nil)

      # Simply high - low = 105 - 99 = 6
      assert Decimal.equal?(result, Decimal.new("6.0"))
    end

    test "true_range_series/1 calculates true range for data series", %{data: data} do
      results = Utils.true_range_series(data)

      # Should have same length as input data
      assert length(results) == length(data)

      # First TR should be just H-L
      first_tr = Enum.at(results, 0)
      # H - L for first period
      expected_first = Decimal.new("6.0")
      assert Decimal.equal?(first_tr, expected_first)

      # All results should be positive or zero
      assert Enum.all?(results, fn val -> Decimal.compare(val, Decimal.new("0")) != :lt end)
    end

    test "true_range_series/1 handles empty data" do
      assert Utils.true_range_series([]) == []
    end
  end

  describe "utility functions" do
    test "round_to/2 rounds to specified precision" do
      assert Decimal.equal?(Utils.round_to(Decimal.new("3.14159"), 2), Decimal.new("3.14"))
      assert Decimal.equal?(Utils.round_to(Decimal.new("3.14159"), 4), Decimal.new("3.1416"))
      assert Decimal.equal?(Utils.round_to(Decimal.new("3.14159"), 0), Decimal.new("3"))
      # default precision
      assert Decimal.equal?(Utils.round_to(Decimal.new("3.14159")), Decimal.new("3.14"))
    end

    test "all_decimals?/1 validates decimal lists" do
      assert Utils.all_decimals?([Decimal.new("1"), Decimal.new("2"), Decimal.new("3")])
      assert Utils.all_decimals?([Decimal.new("1.5"), Decimal.new("2.7"), Decimal.new("3")])
      assert Utils.all_decimals?([])

      refute Utils.all_decimals?([Decimal.new("1"), "2", Decimal.new("3")])
      refute Utils.all_decimals?([Decimal.new("1"), nil, Decimal.new("3")])
      refute Utils.all_decimals?([:a, :b, :c])
    end

    test "all_numbers?/1 validates decimal lists (legacy)" do
      assert Utils.all_numbers?([Decimal.new("1"), Decimal.new("2"), Decimal.new("3")])
      assert Utils.all_numbers?([Decimal.new("1.5"), Decimal.new("2.7"), Decimal.new("3")])
      assert Utils.all_numbers?([])

      refute Utils.all_numbers?([Decimal.new("1"), "2", Decimal.new("3")])
      refute Utils.all_numbers?([Decimal.new("1"), nil, Decimal.new("3")])
      refute Utils.all_numbers?([:a, :b, :c])
    end

    test "forward_fill/2 fills missing values" do
      data = [Decimal.new("1"), nil, Decimal.new("3"), nil, nil, Decimal.new("6")]
      result = Utils.forward_fill(data)

      expected = [
        Decimal.new("1"),
        Decimal.new("1"),
        Decimal.new("3"),
        Decimal.new("3"),
        Decimal.new("3"),
        Decimal.new("6")
      ]

      assert result == expected
    end

    test "forward_fill/2 handles edge cases" do
      # Starting with nil
      assert Utils.forward_fill([nil, Decimal.new("2"), nil, Decimal.new("4")], Decimal.new("0")) ==
               [Decimal.new("0"), Decimal.new("2"), Decimal.new("2"), Decimal.new("4")]

      # All nil
      assert Utils.forward_fill([nil, nil, nil], Decimal.new("5")) == [
               Decimal.new("5"),
               Decimal.new("5"),
               Decimal.new("5")
             ]

      # No nil values
      assert Utils.forward_fill(
               [Decimal.new("1"), Decimal.new("2"), Decimal.new("3")],
               Decimal.new("0")
             ) == [Decimal.new("1"), Decimal.new("2"), Decimal.new("3")]

      # Empty list
      assert Utils.forward_fill([], Decimal.new("0")) == []
    end
  end

  describe "property-based testing" do
    test "mean is always between min and max values" do
      # Generate random data for property testing
      ohlcv_data = DataGenerator.sample_prices(100)
      # Extract closing prices
      data = Utils.extract_closes(ohlcv_data)
      mean_val = Utils.mean(data)

      min_val = Enum.min(data, Decimal)
      max_val = Enum.max(data, Decimal)

      assert Decimal.compare(mean_val, min_val) != :lt
      assert Decimal.compare(mean_val, max_val) != :gt
    end

    test "standard deviation is always non-negative" do
      # Test with various data sets
      for _i <- 1..10 do
        ohlcv_data = DataGenerator.sample_prices(50)
        # Extract closing prices
        data = Utils.extract_closes(ohlcv_data)
        std_dev = Utils.standard_deviation(data)

        assert Decimal.compare(std_dev, Decimal.new("0.0")) != :lt
      end
    end

    test "sliding window preserves data order" do
      # Use unique values to avoid issues with duplicate matching
      data = Enum.map(1..20, fn i -> Decimal.new("#{i}.#{i}") end)
      windows = Utils.sliding_window(data, 5)

      # Each window should maintain the original order
      Enum.each(windows, fn window ->
        assert length(window) == 5

        # Check that elements are in ascending index order from original data
        indices = Enum.map(window, fn val -> Enum.find_index(data, &Decimal.equal?(&1, val)) end)
        assert indices == Enum.sort(indices)
      end)
    end
  end
end
