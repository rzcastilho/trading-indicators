defmodule TradingIndicatorsTest do
  use ExUnit.Case, async: true
  require Decimal

  alias TradingIndicators.TestSupport.DataGenerator

  doctest TradingIndicators

  describe "version/0" do
    test "returns the current version" do
      version = TradingIndicators.version()
      assert is_binary(version)
      assert String.match?(version, ~r/\d+\.\d+\.\d+/)
    end
  end

  describe "categories/0" do
    test "returns list of indicator categories" do
      categories = TradingIndicators.categories()
      assert is_list(categories)
      # Currently empty in Phase 1, will be populated in later phases
    end
  end

  describe "validate_data/1" do
    test "returns :ok for valid OHLCV data" do
      data = DataGenerator.known_test_data()
      assert TradingIndicators.validate_data(data) == :ok
    end

    test "returns error for empty data" do
      {:error, error} = TradingIndicators.validate_data([])
      assert error.message =~ "Data series cannot be empty"
      assert error.required == 1
      assert error.provided == 0
    end

    test "returns error for invalid data format" do
      {:error, error} = TradingIndicators.validate_data("invalid")
      assert error.message =~ "Data must be a list of OHLCV maps"
    end

    test "returns error for invalid OHLCV data point" do
      invalid_data = [
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("105.0"),
          low: Decimal.new("99.0"),
          close: Decimal.new("103.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        # Missing required fields
        %{high: Decimal.new("107.0"), low: Decimal.new("102.0"), close: Decimal.new("106.0")}
      ]

      {:error, error} = TradingIndicators.validate_data(invalid_data)
      assert error.message =~ "Invalid OHLCV data at index 1"
      assert error.index == 1
    end
  end

  describe "extract_price_series/2" do
    setup do
      data = DataGenerator.known_test_data()
      {:ok, data: data}
    end

    test "extracts closing prices", %{data: data} do
      closes = TradingIndicators.extract_price_series(data, :close)

      expected = [
        Decimal.new("103.0"),
        Decimal.new("106.0"),
        Decimal.new("105.0"),
        Decimal.new("108.0"),
        Decimal.new("107.0")
      ]

      assert closes == expected
    end

    test "extracts opening prices", %{data: data} do
      opens = TradingIndicators.extract_price_series(data, :open)

      expected = [
        Decimal.new("100.0"),
        Decimal.new("103.0"),
        Decimal.new("106.0"),
        Decimal.new("105.0"),
        Decimal.new("108.0")
      ]

      assert opens == expected
    end

    test "extracts high prices", %{data: data} do
      highs = TradingIndicators.extract_price_series(data, :high)

      expected = [
        Decimal.new("105.0"),
        Decimal.new("107.0"),
        Decimal.new("108.0"),
        Decimal.new("109.0"),
        Decimal.new("110.0")
      ]

      assert highs == expected
    end

    test "extracts low prices", %{data: data} do
      lows = TradingIndicators.extract_price_series(data, :low)

      expected = [
        Decimal.new("99.0"),
        Decimal.new("102.0"),
        Decimal.new("104.0"),
        Decimal.new("103.0"),
        Decimal.new("106.0")
      ]

      assert lows == expected
    end
  end

  describe "create_result/3" do
    test "creates standardized indicator result with metadata" do
      value = Decimal.new("14.5")
      timestamp = ~U[2024-01-01 09:30:00Z]
      metadata = %{period: 14, source: :close}

      result = TradingIndicators.create_result(value, timestamp, metadata)

      assert result.value == value
      assert result.timestamp == timestamp
      assert result.metadata == metadata
    end

    test "creates result with empty metadata by default" do
      value = Decimal.new("42.0")
      timestamp = ~U[2024-01-01 10:00:00Z]

      result = TradingIndicators.create_result(value, timestamp)

      assert result.value == value
      assert result.timestamp == timestamp
      assert result.metadata == %{}
    end

    test "accepts complex values" do
      value = %{macd: Decimal.new("1.5"), signal: Decimal.new("1.2"), histogram: Decimal.new("0.3")}
      timestamp = ~U[2024-01-01 09:30:00Z]

      result = TradingIndicators.create_result(value, timestamp)

      assert result.value == value
      assert result.timestamp == timestamp
    end
  end

  describe "integration with test support" do
    test "generates valid OHLCV data" do
      data = DataGenerator.sample_ohlcv_data(10)

      assert length(data) == 10
      assert TradingIndicators.validate_data(data) == :ok

      # Test price extraction works with generated data
      closes = TradingIndicators.extract_price_series(data, :close)
      assert length(closes) == 10
      assert Enum.all?(closes, &Decimal.is_decimal/1)
    end

    test "known test data is valid and consistent" do
      data = DataGenerator.known_test_data()

      assert TradingIndicators.validate_data(data) == :ok
      assert length(data) == 5

      # Verify the data structure is correct
      first_point = List.first(data)
      assert Decimal.equal?(first_point.open, Decimal.new("100.0"))
      assert Decimal.equal?(first_point.close, Decimal.new("103.0"))
    end
  end
end
