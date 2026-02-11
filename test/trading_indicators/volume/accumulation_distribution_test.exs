defmodule TradingIndicators.Volume.AccumulationDistributionTest do
  use ExUnit.Case, async: true
  alias TradingIndicators.Volume.AccumulationDistribution
  require Decimal

  doctest AccumulationDistribution

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
    test "calculates A/D Line correctly for basic data series" do
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

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 2

      # First: MF Multiplier = ((103-99) - (105-103)) / (105-99) = (4-2)/6 = 1/3 = 0.333333
      # First: MF Volume = 0.333333 * 1000 = 333.333333
      first = Enum.at(results, 0)
      expected_first = Decimal.div(Decimal.new("1000"), Decimal.new("3"))
      assert Decimal.equal?(first.value, expected_first)

      # Second: MF Multiplier = ((106-102) - (107-106)) / (107-102) = (4-1)/5 = 3/5 = 0.6
      # Second: MF Volume = 0.6 * 1500 = 900
      # Second A/D = 333.333333 + 900 = 1233.333333
      second = Enum.at(results, 1)
      expected_second = Decimal.add(expected_first, Decimal.new("900"))
      assert Decimal.equal?(second.value, expected_second)
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

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 2

      # First: MF Multiplier = 0 when High = Low
      # First: MF Volume = 0 * 1000 = 0
      first = Enum.at(results, 0)
      assert Decimal.equal?(first.value, Decimal.new("0.000000"))

      # Second: MF Multiplier = ((101-101) - (102-101)) / (102-101) = (0-1)/1 = -1
      # Second: MF Volume = -1 * 1500 = -1500
      # Second A/D = 0 + (-1500) = -1500
      second = Enum.at(results, 1)
      assert Decimal.equal?(second.value, Decimal.new("-1500.000000"))
    end

    test "handles close at high (bullish signal)" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("105"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      # MF Multiplier = ((105-99) - (105-105)) / (105-99) = (6-0)/6 = 1
      # MF Volume = 1 * 1000 = 1000
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("1000.000000"))
      assert Decimal.equal?(result.metadata.money_flow_multiplier, Decimal.new("1.000000"))
    end

    test "handles close at low (bearish signal)" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("99"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      # MF Multiplier = ((99-99) - (105-99)) / (105-99) = (0-6)/6 = -1
      # MF Volume = -1 * 1000 = -1000
      result = Enum.at(results, 0)
      assert Decimal.equal?(result.value, Decimal.new("-1000.000000"))
      assert Decimal.equal?(result.metadata.money_flow_multiplier, Decimal.new("-1.000000"))
    end

    test "handles single data point" do
      data = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("99"),
          close: Decimal.new("103"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 1
      # Should equal the Money Flow Volume of the single period
      expected = Decimal.div(Decimal.new("1000"), Decimal.new("3"))
      assert Decimal.equal?(Enum.at(results, 0).value, expected)
    end

    test "handles zero volume correctly" do
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
        }
      ]

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 2

      first = Enum.at(results, 0)
      expected_first = Decimal.div(Decimal.new("1000"), Decimal.new("3"))
      assert Decimal.equal?(first.value, expected_first)

      # Second: MF Volume = 0.6 * 0 = 0
      # A/D remains unchanged
      second = Enum.at(results, 1)
      assert Decimal.equal?(second.value, expected_first)
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

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      result = Enum.at(results, 0)
      assert result.metadata.indicator == "AccumulationDistribution"
      expected_multiplier = Decimal.div(Decimal.new("1"), Decimal.new("3"))

      assert Decimal.equal?(
               result.metadata.money_flow_multiplier,
               expected_multiplier
             )

      expected_mf_volume = Decimal.div(Decimal.new("1000"), Decimal.new("3"))

      assert Decimal.equal?(
               result.metadata.money_flow_volume,
               expected_mf_volume
             )

      assert result.metadata.volume == 1000
      assert Decimal.equal?(result.metadata.close, Decimal.new("103"))
      assert Decimal.equal?(result.metadata.high, Decimal.new("105"))
      assert Decimal.equal?(result.metadata.low, Decimal.new("99"))
    end

    test "returns error for insufficient data" do
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} =
               AccumulationDistribution.calculate([], [])
    end

    test "returns error for invalid parameters" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               AccumulationDistribution.calculate(@test_data, period: 14)
    end

    test "returns error for invalid data format" do
      invalid_data = [%{price: Decimal.new("100"), vol: 1000}]

      assert {:error, %TradingIndicators.Errors.InvalidDataFormat{}} =
               AccumulationDistribution.calculate(invalid_data, [])
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
               AccumulationDistribution.calculate(invalid_data, [])
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
               AccumulationDistribution.calculate(invalid_data, [])
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
               AccumulationDistribution.calculate(invalid_data, [])
    end
  end

  describe "validate_params/1" do
    test "accepts empty options" do
      assert :ok == AccumulationDistribution.validate_params([])
    end

    test "rejects non-empty options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               AccumulationDistribution.validate_params(period: 14)
    end

    test "rejects non-keyword list options" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} =
               AccumulationDistribution.validate_params("invalid")
    end
  end

  describe "required_periods/0" do
    test "returns minimum periods required" do
      assert AccumulationDistribution.required_periods() == 1
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes properly" do
      state = AccumulationDistribution.init_state([])

      assert state.ad_line_value == nil
      assert state.count == 0
    end

    test "update_state/2 handles first data point" do
      state = AccumulationDistribution.init_state([])

      data_point = %{
        high: Decimal.new("105"),
        low: Decimal.new("99"),
        close: Decimal.new("103"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      {:ok, new_state, result} = AccumulationDistribution.update_state(state, data_point)

      expected_mf_volume = Decimal.div(Decimal.new("1000"), Decimal.new("3"))
      assert Decimal.equal?(new_state.ad_line_value, expected_mf_volume)
      assert new_state.count == 1
      assert Decimal.equal?(result.value, expected_mf_volume)
    end

    test "update_state/2 handles subsequent data points" do
      # Start with existing A/D Line value
      expected_first = Decimal.div(Decimal.new("1000"), Decimal.new("3"))

      state = %{
        ad_line_value: expected_first,
        count: 1
      }

      data_point = %{
        high: Decimal.new("107"),
        low: Decimal.new("102"),
        close: Decimal.new("106"),
        volume: 1500,
        timestamp: ~U[2024-01-01 09:31:00Z]
      }

      {:ok, new_state, result} = AccumulationDistribution.update_state(state, data_point)

      # MF Multiplier = ((106-102) - (107-106)) / (107-102) = (4-1)/5 = 0.6
      # MF Volume = 0.6 * 1500 = 900
      # New A/D = 333.333333 + 900 = 1233.333333
      expected_new = Decimal.add(expected_first, Decimal.new("900"))
      assert Decimal.equal?(new_state.ad_line_value, expected_new)
      assert new_state.count == 2
      assert Decimal.equal?(result.value, expected_new)
    end

    test "update_state/2 handles equal high/low (no price range)" do
      state = %{
        ad_line_value: Decimal.new("1000"),
        count: 1
      }

      data_point = %{
        high: Decimal.new("100"),
        low: Decimal.new("100"),
        close: Decimal.new("100"),
        volume: 1500,
        timestamp: ~U[2024-01-01 09:31:00Z]
      }

      {:ok, new_state, result} = AccumulationDistribution.update_state(state, data_point)

      # MF Volume should be 0 when High = Low
      # No change
      assert Decimal.equal?(new_state.ad_line_value, Decimal.new("1000"))
      assert Decimal.equal?(result.value, Decimal.new("1000.000000"))
      assert Decimal.equal?(result.metadata.money_flow_multiplier, Decimal.new("0.000000"))
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
               AccumulationDistribution.update_state(invalid_state, data_point)
    end

    test "update_state/2 handles invalid data point" do
      state = AccumulationDistribution.init_state([])
      invalid_data = %{price: 100, vol: 1000}

      assert {:error, %TradingIndicators.Errors.StreamStateError{}} =
               AccumulationDistribution.update_state(state, invalid_data)
    end
  end

  describe "money flow calculations" do
    test "calculates money flow multiplier correctly for various positions" do
      test_cases = [
        # Close at middle
        {Decimal.new("105"), Decimal.new("99"), Decimal.new("102"), Decimal.new("0")},
        # Close at 75% of range (bullish)
        {Decimal.new("104"), Decimal.new("100"), Decimal.new("103"), Decimal.new("0.5")},
        # Close at 25% of range (bearish)
        {Decimal.new("104"), Decimal.new("100"), Decimal.new("101"), Decimal.new("-0.5")}
      ]

      for {high, low, close, expected_multiplier} <- test_cases do
        data = [
          %{high: high, low: low, close: close, volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
        ]

        {:ok, results} = AccumulationDistribution.calculate(data, [])

        result = Enum.at(results, 0)

        assert Decimal.equal?(result.metadata.money_flow_multiplier, expected_multiplier),
               "Failed for high=#{high}, low=#{low}, close=#{close}. Expected=#{expected_multiplier}, Got=#{result.metadata.money_flow_multiplier}"
      end
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

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 2
      # Should maintain precision even with large numbers
      last_result = List.last(results)
      assert Decimal.is_decimal(last_result.value)
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

      {:ok, results} = AccumulationDistribution.calculate(data, [])

      assert length(results) == 2
      # Verify precision is maintained
      last_result = List.last(results)
      assert Decimal.is_decimal(last_result.value)
    end

    test "handles many periods efficiently" do
      # Generate 1000 data points with alternating bullish/bearish signals
      large_data =
        1..1000
        |> Enum.map(fn i ->
          base_price = 100

          if rem(i, 2) == 0 do
            # Bullish period - close near high
            %{
              high: Decimal.new("#{base_price + 5}"),
              low: Decimal.new("#{base_price}"),
              close: Decimal.new("#{base_price + 4}"),
              volume: 1000 + i,
              timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :second)
            }
          else
            # Bearish period - close near low
            %{
              high: Decimal.new("#{base_price + 5}"),
              low: Decimal.new("#{base_price}"),
              close: Decimal.new("#{base_price + 1}"),
              volume: 1000 + i,
              timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :second)
            }
          end
        end)

      {:ok, results} = AccumulationDistribution.calculate(large_data, [])

      assert length(results) == 1000
      # Verify last result makes sense
      last_result = List.last(results)
      assert Decimal.is_decimal(last_result.value)
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = AccumulationDistribution.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = AccumulationDistribution.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
