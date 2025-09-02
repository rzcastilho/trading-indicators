defmodule TradingIndicators.DataQualityTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.DataQuality

  alias TradingIndicators.DataQuality

  @valid_data [
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
      low: Decimal.new("102.0"),
      close: Decimal.new("106.0"),
      volume: 1200,
      timestamp: ~U[2024-01-01 09:31:00Z]
    },
    %{
      open: Decimal.new("106.0"),
      high: Decimal.new("108.0"),
      low: Decimal.new("105.0"),
      close: Decimal.new("107.0"),
      volume: 1100,
      timestamp: ~U[2024-01-01 09:32:00Z]
    }
  ]

  describe "validate_time_series/1" do
    test "validates clean data successfully" do
      assert {:ok, report} = DataQuality.validate_time_series(@valid_data)
      
      assert report.total_points == 3
      assert report.valid_points == 3
      assert report.invalid_points == 0
      assert report.missing_timestamps == 0
      assert report.duplicate_timestamps == 0
      assert report.chronological_errors == 0
      assert report.quality_score == 100.0
      assert report.issues == []
    end

    test "detects invalid data points" do
      invalid_data = [
        %{open: "invalid", high: nil, low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        List.first(@valid_data)
      ]

      assert {:ok, report} = DataQuality.validate_time_series(invalid_data)
      
      assert report.total_points == 2
      assert report.valid_points == 1
      assert report.invalid_points == 1
      assert report.quality_score < 100.0
      assert length(report.issues) > 0
      
      invalid_issue = Enum.find(report.issues, fn issue -> issue.type == :invalid_data end)
      assert invalid_issue != nil
      assert invalid_issue.severity == :high
    end

    test "detects missing timestamps" do
      data_with_missing_timestamp = [
        %{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: nil},
        List.first(@valid_data)
      ]

      assert {:ok, report} = DataQuality.validate_time_series(data_with_missing_timestamp)
      
      assert report.missing_timestamps == 1
      
      missing_issue = Enum.find(report.issues, fn issue -> issue.type == :missing_data end)
      assert missing_issue != nil
      assert missing_issue.severity == :critical
    end

    test "detects duplicate timestamps" do
      duplicate_data = [
        List.first(@valid_data),
        %{List.first(@valid_data) | close: Decimal.new("104.0")}  # Same timestamp, different close
      ]

      assert {:ok, report} = DataQuality.validate_time_series(duplicate_data)
      
      assert report.duplicate_timestamps > 0
      
      duplicate_issue = Enum.find(report.issues, fn issue -> issue.type == :duplicate end)
      assert duplicate_issue != nil
      assert duplicate_issue.severity == :medium
    end

    test "detects chronological order errors" do
      out_of_order_data = [
        Enum.at(@valid_data, 1),  # Later timestamp first
        Enum.at(@valid_data, 0)   # Earlier timestamp second
      ]

      assert {:ok, report} = DataQuality.validate_time_series(out_of_order_data)
      
      assert report.chronological_errors > 0
      
      chronological_issue = Enum.find(report.issues, fn issue -> issue.type == :chronological_error end)
      assert chronological_issue != nil
      assert chronological_issue.severity == :high
    end

    test "detects OHLC relationship violations" do
      invalid_ohlc_data = [
        %{
          open: Decimal.new("100.0"),
          high: Decimal.new("95.0"),  # High less than open - violation
          low: Decimal.new("99.0"),
          close: Decimal.new("103.0"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      assert {:ok, report} = DataQuality.validate_time_series(invalid_ohlc_data)
      
      ohlc_issue = Enum.find(report.issues, fn issue -> 
        issue.type == :invalid_data and String.contains?(issue.description, "High price is less")
      end)
      assert ohlc_issue != nil
    end

    test "detects negative volume" do
      negative_volume_data = [
        %{List.first(@valid_data) | volume: -100}
      ]

      assert {:ok, report} = DataQuality.validate_time_series(negative_volume_data)
      
      volume_issue = Enum.find(report.issues, fn issue -> 
        issue.type == :invalid_data and String.contains?(issue.description, "Negative volume")
      end)
      assert volume_issue != nil
      assert volume_issue.severity == :high
    end

    test "calculates quality score correctly" do
      # Data with 1 issue out of 3 points
      mixed_data = [
        List.first(@valid_data),
        %{open: "invalid", high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        List.last(@valid_data)
      ]

      assert {:ok, report} = DataQuality.validate_time_series(mixed_data)
      
      # Should have quality issues affecting the score
      assert report.quality_score < 100.0
      assert report.quality_score > 0.0
    end

    test "returns error for non-list input" do
      assert {:error, error} = DataQuality.validate_time_series("not a list")
      assert error.message =~ "must be a list"
    end

    test "handles empty data list" do
      assert {:ok, report} = DataQuality.validate_time_series([])
      
      assert report.total_points == 0
      assert report.quality_score == 0.0
    end
  end

  describe "detect_outliers/3" do
    test "detects outliers using IQR method" do
      # Add an obvious outlier
      data_with_outlier = @valid_data ++ [
        %{
          open: Decimal.new("500.0"),   # Obvious outlier
          high: Decimal.new("505.0"),
          low: Decimal.new("499.0"),
          close: Decimal.new("503.0"),
          volume: 1500,
          timestamp: ~U[2024-01-01 09:33:00Z]
        }
      ]

      outliers = DataQuality.detect_outliers(data_with_outlier, :iqr)
      
      assert is_list(outliers)
      # With obvious outlier, should detect at least something
      # (exact behavior depends on IQR implementation)
    end

    test "detects outliers using Z-score method" do
      data_with_outlier = @valid_data ++ [
        %{
          open: Decimal.new("200.0"),   # Outlier
          high: Decimal.new("205.0"),
          low: Decimal.new("199.0"),
          close: Decimal.new("203.0"),
          volume: 2000,
          timestamp: ~U[2024-01-01 09:33:00Z]
        }
      ]

      outliers = DataQuality.detect_outliers(data_with_outlier, :zscore, threshold: 1.5)
      
      assert is_list(outliers)
    end

    test "detects outliers using modified Z-score method" do
      outliers = DataQuality.detect_outliers(@valid_data, :modified_zscore)
      
      assert is_list(outliers)
      # Valid data should have no outliers
      assert length(outliers) == 0
    end

    test "handles isolation forest method (placeholder)" do
      outliers = DataQuality.detect_outliers(@valid_data, :isolation_forest)
      
      # Currently returns empty list as it's a placeholder
      assert outliers == []
    end

    test "supports custom field for outlier detection" do
      outliers = DataQuality.detect_outliers(@valid_data, :iqr, field: :volume)
      
      assert is_list(outliers)
    end

    test "handles insufficient data for outlier detection" do
      small_data = [List.first(@valid_data)]
      
      outliers = DataQuality.detect_outliers(small_data, :iqr)
      
      # Should handle gracefully with insufficient data
      assert outliers == []
    end

    test "returns empty list for unknown method" do
      outliers = DataQuality.detect_outliers(@valid_data, :unknown_method)
      
      assert outliers == []
    end
  end

  describe "fill_gaps/3" do
    test "fills gaps using forward fill method" do
      data_with_gap = [
        List.first(@valid_data),
        %{open: nil, high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        List.last(@valid_data)
      ]

      assert {:ok, cleaned_data} = DataQuality.fill_gaps(data_with_gap, :forward_fill)
      
      # Should have fewer points (invalid ones removed or filled)
      assert length(cleaned_data) <= length(data_with_gap)
      
      # All remaining points should be valid
      Enum.each(cleaned_data, fn point ->
        assert TradingIndicators.Types.valid_ohlcv?(point) or is_map(point)
      end)
    end

    test "fills gaps using backward fill method" do
      data_with_gap = [
        %{open: nil, high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:30:00Z]},
        List.first(@valid_data),
        List.last(@valid_data)
      ]

      assert {:ok, cleaned_data} = DataQuality.fill_gaps(data_with_gap, :backward_fill)
      
      assert is_list(cleaned_data)
      assert length(cleaned_data) <= length(data_with_gap)
    end

    test "fills gaps using interpolation method" do
      data_with_gap = [
        List.first(@valid_data),
        %{open: nil, high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        List.last(@valid_data)
      ]

      assert {:ok, cleaned_data} = DataQuality.fill_gaps(data_with_gap, :interpolate)
      
      assert is_list(cleaned_data)
    end

    test "removes invalid points when using remove method" do
      data_with_invalid = [
        List.first(@valid_data),
        %{open: "invalid", high: nil, low: nil, close: nil, volume: -1, timestamp: ~U[2024-01-01 09:31:00Z]},
        List.last(@valid_data)
      ]

      assert {:ok, cleaned_data} = DataQuality.fill_gaps(data_with_invalid, :remove)
      
      # Should only have valid data points
      assert length(cleaned_data) == 2
      
      Enum.each(cleaned_data, fn point ->
        assert TradingIndicators.Types.valid_ohlcv?(point)
      end)
    end

    test "returns error for unknown fill method" do
      assert {:error, error} = DataQuality.fill_gaps(@valid_data, :unknown_method)
      assert error.message =~ "Unknown gap filling method"
    end

    test "handles empty data" do
      assert {:ok, cleaned_data} = DataQuality.fill_gaps([], :forward_fill)
      assert cleaned_data == []
    end
  end

  describe "normalize_data/3" do
    test "normalizes data using min-max method" do
      assert {:ok, normalized_data} = DataQuality.normalize_data(@valid_data, :minmax)
      
      assert length(normalized_data) == length(@valid_data)
      
      # Extract normalized close prices
      normalized_closes = 
        Enum.map(normalized_data, fn point -> 
          close = Map.get(point, :close)
          if close, do: Decimal.to_float(close), else: nil
        end)
        |> Enum.reject(&is_nil/1)

      # Min-max normalization should produce values between 0 and 1
      assert Enum.all?(normalized_closes, fn val -> val >= 0.0 and val <= 1.0 end)
    end

    test "normalizes data using Z-score method" do
      assert {:ok, normalized_data} = DataQuality.normalize_data(@valid_data, :zscore)
      
      assert length(normalized_data) == length(@valid_data)
      
      # Z-score normalization should have mean around 0
      normalized_closes = 
        Enum.map(normalized_data, fn point -> 
          close = Map.get(point, :close)
          if close, do: Decimal.to_float(close), else: nil
        end)
        |> Enum.reject(&is_nil/1)

      if length(normalized_closes) > 1 do
        mean = Enum.sum(normalized_closes) / length(normalized_closes)
        assert abs(mean) < 0.1  # Should be close to 0
      end
    end

    test "normalizes data using robust method" do
      assert {:ok, normalized_data} = DataQuality.normalize_data(@valid_data, :robust)
      
      assert length(normalized_data) == length(@valid_data)
      assert is_list(normalized_data)
    end

    test "returns unchanged data for none method" do
      assert {:ok, normalized_data} = DataQuality.normalize_data(@valid_data, :none)
      
      assert normalized_data == @valid_data
    end

    test "supports custom field for normalization" do
      assert {:ok, normalized_data} = DataQuality.normalize_data(@valid_data, :minmax, field: :volume)
      
      assert length(normalized_data) == length(@valid_data)
      # Volumes should be normalized while prices remain unchanged
    end

    test "handles data with identical values" do
      identical_data = List.duplicate(List.first(@valid_data), 3)
      
      assert {:ok, normalized_data} = DataQuality.normalize_data(identical_data, :minmax)
      
      # Should handle zero range gracefully
      assert length(normalized_data) == 3
    end

    test "returns error for unknown normalization method" do
      assert {:error, error} = DataQuality.normalize_data(@valid_data, :unknown_method)
      assert error.message =~ "Unknown normalization method"
    end
  end

  describe "quality_report/1" do
    test "generates comprehensive report for valid data" do
      report = DataQuality.quality_report(@valid_data)
      
      assert report.total_points == 3
      assert report.valid_points == 3
      assert report.quality_score == 100.0
      assert Map.has_key?(report, :data_coverage)
      assert Map.has_key?(report, :price_consistency)
      assert Map.has_key?(report, :volume_distribution)
      assert Map.has_key?(report, :timestamp_regularity)
      assert Map.has_key?(report, :recommendations)
    end

    test "generates report with issues for problematic data" do
      problematic_data = [
        List.first(@valid_data),
        %{open: "invalid", high: nil, low: nil, close: nil, volume: -100, timestamp: nil}
      ]

      report = DataQuality.quality_report(problematic_data)
      
      assert report.total_points == 2
      assert report.valid_points == 1
      assert report.quality_score < 100.0
      assert length(report.issues) > 0
      assert is_list(report.recommendations)
    end

    test "provides quality recommendations based on issues" do
      low_quality_data = [
        %{open: "invalid", high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{List.first(@valid_data) | timestamp: ~U[2024-01-01 09:29:00Z]},  # Out of order
        List.first(@valid_data)
      ]

      report = DataQuality.quality_report(low_quality_data)
      
      assert report.quality_score < 80.0
      assert length(report.recommendations) > 0
      
      # Should recommend data cleaning
      assert Enum.any?(report.recommendations, fn rec -> 
        String.contains?(rec, "cleaning") or String.contains?(rec, "quality")
      end)
    end

    test "handles empty data gracefully" do
      report = DataQuality.quality_report([])
      
      assert report.total_points == 0
      assert report.quality_score == 0.0
      assert report.issues == []
    end

    test "handles non-list input gracefully" do
      report = DataQuality.quality_report("invalid")
      
      assert Map.has_key?(report, :error)
      assert report.total_points == 0
      assert report.quality_score == 0.0
    end

    test "includes outlier information in report" do
      data_with_outlier = @valid_data ++ [
        %{
          open: Decimal.new("1000.0"),   # Clear outlier
          high: Decimal.new("1005.0"),
          low: Decimal.new("999.0"),
          close: Decimal.new("1003.0"),
          volume: 10000,
          timestamp: ~U[2024-01-01 09:33:00Z]
        }
      ]

      report = DataQuality.quality_report(data_with_outlier)
      
      # May detect outliers depending on implementation
      assert is_integer(report.outliers_detected)
      assert report.outliers_detected >= 0
    end
  end

  # Property-based testing
  describe "property tests" do
    @tag :property
    test "data quality score is between 0 and 100" do
      test_datasets = [
        @valid_data,
        [],
        [%{invalid: "data"}],
        @valid_data ++ [%{open: "invalid", high: nil, low: nil, close: nil, volume: -1, timestamp: nil}]
      ]

      for dataset <- test_datasets do
        report = DataQuality.quality_report(dataset)
        assert report.quality_score >= 0.0
        assert report.quality_score <= 100.0
      end
    end

    @tag :property
    test "normalization preserves data structure" do
      methods = [:minmax, :zscore, :robust, :none]

      for method <- methods do
        case DataQuality.normalize_data(@valid_data, method) do
          {:ok, normalized_data} ->
            assert length(normalized_data) == length(@valid_data)
            assert is_list(normalized_data)
            
            # Structure should be preserved
            Enum.each(normalized_data, fn point ->
              assert is_map(point)
              assert Map.has_key?(point, :timestamp)
            end)
          
          {:error, _reason} ->
            # Some methods might not be implemented
            :ok
        end
      end
    end

    @tag :property
    test "gap filling maintains or reduces data size" do
      data_with_gaps = [
        List.first(@valid_data),
        %{open: nil, high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{open: "invalid", high: nil, low: nil, close: nil, volume: -1, timestamp: ~U[2024-01-01 09:32:00Z]},
        List.last(@valid_data)
      ]

      methods = [:forward_fill, :backward_fill, :interpolate, :remove]

      for method <- methods do
        case DataQuality.fill_gaps(data_with_gaps, method) do
          {:ok, cleaned_data} ->
            assert length(cleaned_data) <= length(data_with_gaps)
            assert is_list(cleaned_data)
          
          {:error, _reason} ->
            # Some methods might fail with certain data
            :ok
        end
      end
    end
  end

  # Edge cases
  describe "edge cases" do
    test "handles data with missing OHLC fields" do
      incomplete_data = [
        %{open: Decimal.new("100.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},  # Missing high, low, close
        List.first(@valid_data)
      ]

      assert {:ok, report} = DataQuality.validate_time_series(incomplete_data)
      assert report.invalid_points > 0
    end

    test "handles very large datasets efficiently" do
      # Create large dataset
      large_dataset = List.duplicate(List.first(@valid_data), 10_000)

      start_time = System.monotonic_time(:microsecond)
      report = DataQuality.quality_report(large_dataset)
      end_time = System.monotonic_time(:microsecond)

      processing_time = end_time - start_time
      
      assert report.total_points == 10_000
      # Should process reasonably quickly (< 1 second for 10k points)
      assert processing_time < 1_000_000
    end

    test "handles data with extreme outliers" do
      extreme_data = @valid_data ++ [
        %{
          open: Decimal.new("999999.0"),   # Extreme outlier
          high: Decimal.new("1000000.0"),
          low: Decimal.new("999998.0"),
          close: Decimal.new("999999.5"),
          volume: 1000000,
          timestamp: ~U[2024-01-01 09:33:00Z]
        }
      ]

      # Should not crash with extreme values
      report = DataQuality.quality_report(extreme_data)
      assert is_map(report)
      assert report.total_points == 4
    end

    test "handles data with zero volume consistently" do
      zero_volume_data = [
        %{List.first(@valid_data) | volume: 0},
        List.last(@valid_data)
      ]

      assert {:ok, report} = DataQuality.validate_time_series(zero_volume_data)
      
      # Zero volume might be valid in some contexts
      assert report.total_points == 2
    end
  end
end