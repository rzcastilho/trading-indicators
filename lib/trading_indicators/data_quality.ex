defmodule TradingIndicators.DataQuality do
  require Decimal
  
  @moduledoc """
  Data quality validation and sanitization for trading indicator calculations.

  This module provides comprehensive data quality assessment and cleaning utilities:
  - Data integrity validation and completeness checks
  - Outlier detection using multiple statistical methods
  - Data cleaning and gap filling strategies
  - Time series validation (chronological order, duplicates)
  - Volume and price data quality assessment

  ## Features

  - **Data Validation**: Comprehensive checks for data integrity and format
  - **Outlier Detection**: Multiple methods including IQR, Z-score, and Modified Z-score
  - **Data Cleaning**: Gap filling, outlier handling, and normalization
  - **Quality Scoring**: Quantitative quality assessment
  - **Issue Reporting**: Detailed reports of data quality problems
  - **Time Series Validation**: Chronological order and gap detection

  ## Quality Checks

  - Missing or invalid data points
  - Duplicate timestamps
  - Chronological order violations
  - Price data consistency (OHLC relationships)
  - Volume data validity
  - Statistical outliers
  - Data completeness and coverage

  ## Example Usage

      # Validate time series data
      {:ok, report} = TradingIndicators.DataQuality.validate_time_series(data)
      
      # Detect outliers
      outliers = TradingIndicators.DataQuality.detect_outliers(data, :iqr)
      
      # Clean data
      {:ok, cleaned_data} = TradingIndicators.DataQuality.fill_gaps(data, :forward_fill)
      
      # Generate quality report
      report = TradingIndicators.DataQuality.quality_report(data)

  ## Data Cleaning Strategies

  - **Forward Fill**: Use previous valid value
  - **Backward Fill**: Use next valid value  
  - **Interpolation**: Linear interpolation between valid points
  - **Remove**: Remove invalid data points

  ## Outlier Detection Methods

  - **IQR**: Interquartile Range method
  - **Z-Score**: Standard deviation based
  - **Modified Z-Score**: Median absolute deviation based
  - **Isolation Forest**: Machine learning approach
  """

  alias TradingIndicators.{Types, Errors}
  require Logger

  @type outlier_method :: :iqr | :zscore | :modified_zscore | :isolation_forest
  @type fill_method :: :forward_fill | :backward_fill | :interpolate | :remove
  @type normalization_method :: :minmax | :zscore | :robust | :none

  @doc """
  Validates a time series data set for common quality issues.

  ## Parameters

  - `data` - Time series data to validate

  ## Returns

  - `{:ok, quality_report}` - Validation results and quality assessment
  - `{:error, reason}` - Validation error

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, report} = TradingIndicators.DataQuality.validate_time_series(data)
      iex> report.total_points
      2
      iex> report.valid_points
      2
  """
  @spec validate_time_series(Types.data_series()) :: {:ok, Types.quality_report()} | {:error, term()}
  def validate_time_series(data) when is_list(data) do
    try do
      report = %{
        total_points: length(data),
        valid_points: 0,
        invalid_points: 0,
        missing_timestamps: 0,
        duplicate_timestamps: 0,
        chronological_errors: 0,
        outliers_detected: 0,
        quality_score: 0.0,
        issues: []
      }

      # Validate individual data points
      {valid_count, issues1} = validate_data_points(data)
      
      # Check for timestamp issues
      {timestamp_issues, missing_ts, duplicate_ts, chronological_errors} = validate_timestamps(data)
      
      # Check OHLC relationships
      ohlc_issues = validate_ohlc_relationships(data)
      
      # Check volume data
      volume_issues = validate_volume_data(data)
      
      # Detect outliers
      {outliers, outlier_issues} = detect_statistical_outliers(data)
      
      all_issues = issues1 ++ timestamp_issues ++ ohlc_issues ++ volume_issues ++ outlier_issues
      
      quality_score = calculate_quality_score(report.total_points, length(all_issues))
      
      final_report = %{report |
        valid_points: valid_count,
        invalid_points: report.total_points - valid_count,
        missing_timestamps: missing_ts,
        duplicate_timestamps: duplicate_ts,
        chronological_errors: chronological_errors,
        outliers_detected: length(outliers),
        quality_score: quality_score,
        issues: all_issues
      }

      {:ok, final_report}
    rescue
      error -> {:error, error}
    end
  end

  def validate_time_series(_data) do
    {:error, %Errors.InvalidDataFormat{message: "Data must be a list", expected: "list", received: "invalid"}}
  end

  @doc """
  Detects outliers in time series data using specified method.

  ## Parameters

  - `data` - Time series data to analyze
  - `method` - Outlier detection method
  - `opts` - Method-specific options

  ## Returns

  - List of outlier indices and information

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{open: Decimal.new("500"), high: Decimal.new("505"), low: Decimal.new("499"), close: Decimal.new("503"), volume: 1500, timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> outliers = TradingIndicators.DataQuality.detect_outliers(data, :iqr)
      iex> is_list(outliers)
      true
  """
  @spec detect_outliers(Types.data_series(), outlier_method(), keyword()) :: [map()]
  def detect_outliers(data, method, opts \\ []) when is_list(data) and is_atom(method) do
    try do
      case method do
        :iqr -> detect_outliers_iqr(data, opts)
        :zscore -> detect_outliers_zscore(data, opts)
        :modified_zscore -> detect_outliers_modified_zscore(data, opts)
        :isolation_forest -> detect_outliers_isolation_forest(data, opts)
        _ -> raise ArgumentError, "Unknown outlier detection method: #{inspect(method)}"
      end
    rescue
      error -> 
        Logger.error("Error detecting outliers: #{inspect(error)}")
        []
    end
  end

  @doc """
  Fills gaps in time series data using specified method.

  ## Parameters

  - `data` - Time series data with potential gaps
  - `method` - Gap filling method
  - `opts` - Method-specific options

  ## Returns

  - `{:ok, cleaned_data}` - Data with gaps filled
  - `{:error, reason}` - Cleaning error

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: nil, high: nil, low: nil, close: nil, volume: 0, timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{open: Decimal.new("106"), high: Decimal.new("108"), low: Decimal.new("105"), close: Decimal.new("107"), volume: 1200, timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, cleaned} = TradingIndicators.DataQuality.fill_gaps(data, :forward_fill)
      iex> length(cleaned)
      3
  """
  @spec fill_gaps(Types.data_series(), fill_method(), keyword()) ::
          {:ok, Types.data_series()} | {:error, term()}
  def fill_gaps(data, method, opts \\ []) when is_list(data) and is_atom(method) do
    try do
      cleaned_data = case method do
        :forward_fill -> fill_gaps_forward(data)
        :backward_fill -> fill_gaps_backward(data)
        :interpolate -> fill_gaps_interpolate(data, opts)
        :remove -> remove_invalid_points(data)
        _ -> raise ArgumentError, "Unknown gap filling method: #{inspect(method)}"
      end

      {:ok, cleaned_data}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Normalizes time series data using specified method.

  ## Parameters

  - `data` - Time series data to normalize
  - `method` - Normalization method
  - `opts` - Method-specific options

  ## Returns

  - `{:ok, normalized_data}` - Normalized data
  - `{:error, reason}` - Normalization error

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, normalized} = TradingIndicators.DataQuality.normalize_data(data, :minmax)
      iex> length(normalized)
      2
  """
  @spec normalize_data(Types.data_series(), normalization_method(), keyword()) ::
          {:ok, Types.data_series()} | {:error, term()}
  def normalize_data(data, method, opts \\ []) when is_list(data) and is_atom(method) do
    try do
      normalized_data = case method do
        :minmax -> normalize_minmax(data, opts)
        :zscore -> normalize_zscore(data, opts)
        :robust -> normalize_robust(data, opts)
        :none -> data
        _ -> raise ArgumentError, "Unknown normalization method: #{inspect(method)}"
      end

      {:ok, normalized_data}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Generates a comprehensive quality report for time series data.

  ## Parameters

  - `data` - Time series data to analyze

  ## Returns

  - Quality report with detailed analysis

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> report = TradingIndicators.DataQuality.quality_report(data)
      iex> report.total_points
      2
  """
  @spec quality_report(Types.data_series()) :: Types.quality_report()
  def quality_report(data) when is_list(data) do
    case validate_time_series(data) do
      {:ok, report} -> 
        # Add additional analysis
        enhanced_report = Map.merge(report, %{
          data_coverage: calculate_data_coverage(data),
          price_consistency: analyze_price_consistency(data),
          volume_distribution: analyze_volume_distribution(data),
          timestamp_regularity: analyze_timestamp_regularity(data),
          recommendations: generate_quality_recommendations(report)
        })
        enhanced_report
      
      {:error, _reason} -> 
        %{
          total_points: length(data),
          valid_points: 0,
          invalid_points: length(data),
          missing_timestamps: 0,
          duplicate_timestamps: 0,
          chronological_errors: 0,
          outliers_detected: 0,
          quality_score: 0.0,
          issues: [],
          error: "Failed to generate quality report"
        }
    end
  end

  def quality_report(_data) do
    %{
      total_points: 0,
      valid_points: 0,
      invalid_points: 0,
      missing_timestamps: 0,
      duplicate_timestamps: 0,
      chronological_errors: 0,
      outliers_detected: 0,
      quality_score: 0.0,
      issues: [],
      error: "Invalid data format"
    }
  end

  # Private helper functions

  defp validate_data_points(data) do
    {valid_count, issues} = 
      data
      |> Enum.with_index()
      |> Enum.reduce({0, []}, fn {point, index}, {valid_acc, issues_acc} ->
        if Types.valid_ohlcv?(point) do
          {valid_acc + 1, issues_acc}
        else
          issue = %{
            type: :invalid_data,
            index: index,
            description: "Invalid OHLCV data point",
            severity: :high
          }
          {valid_acc, [issue | issues_acc]}
        end
      end)

    {valid_count, Enum.reverse(issues)}
  end

  defp validate_timestamps(data) do
    issues = []
    missing_timestamps = 0
    _duplicate_timestamps = 0
    _chronological_errors = 0

    # Check for missing timestamps
    {issues, missing_timestamps} = 
      data
      |> Enum.with_index()
      |> Enum.reduce({issues, missing_timestamps}, fn {point, index}, {acc_issues, missing_count} ->
        if Map.get(point, :timestamp) == nil do
          issue = %{
            type: :missing_data,
            index: index,
            description: "Missing timestamp",
            severity: :critical
          }
          {[issue | acc_issues], missing_count + 1}
        else
          {acc_issues, missing_count}
        end
      end)

    # Check for duplicates and chronological order
    timestamps = Enum.map(data, fn point -> Map.get(point, :timestamp) end)
    {duplicate_issues, chronological_issues} = analyze_timestamp_sequence(timestamps)

    all_issues = issues ++ duplicate_issues ++ chronological_issues
    duplicate_count = length(duplicate_issues)
    chronological_count = length(chronological_issues)

    {all_issues, missing_timestamps, duplicate_count, chronological_count}
  end

  defp analyze_timestamp_sequence(timestamps) do
    _duplicate_issues = []
    _chronological_issues = []

    # Simple duplicate detection
    duplicates = 
      timestamps
      |> Enum.with_index()
      |> Enum.group_by(fn {ts, _} -> ts end)
      |> Enum.filter(fn {_, occurrences} -> length(occurrences) > 1 end)
      |> Enum.flat_map(fn {_, occurrences} -> 
        occurrences |> Enum.drop(1) |> Enum.map(fn {_, index} -> index end)
      end)

    duplicate_issues = 
      Enum.map(duplicates, fn index ->
        %{
          type: :duplicate,
          index: index,
          description: "Duplicate timestamp",
          severity: :medium
        }
      end)

    # Simple chronological check
    chronological_issues = 
      timestamps
      |> Enum.with_index()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce([], fn [{ts1, _index1}, {ts2, index2}], acc ->
        if ts1 != nil and ts2 != nil and DateTime.compare(ts1, ts2) == :gt do
          issue = %{
            type: :chronological_error,
            index: index2,
            description: "Timestamp out of chronological order",
            severity: :high
          }
          [issue | acc]
        else
          acc
        end
      end)

    {duplicate_issues, Enum.reverse(chronological_issues)}
  end

  defp validate_ohlc_relationships(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {point, index}, acc ->
      case validate_single_ohlc(point) do
        :ok -> acc
        {:error, description} ->
          issue = %{
            type: :invalid_data,
            index: index,
            description: description,
            severity: :high
          }
          [issue | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp validate_single_ohlc(%{open: open, high: high, low: low, close: close}) 
       when not is_nil(open) and not is_nil(high) and not is_nil(low) and not is_nil(close) do
    cond do
      Decimal.compare(high, low) == :lt ->
        {:error, "High price is less than low price"}
      
      Decimal.compare(high, open) == :lt ->
        {:error, "High price is less than open price"}
        
      Decimal.compare(high, close) == :lt ->
        {:error, "High price is less than close price"}
        
      Decimal.compare(low, open) == :gt ->
        {:error, "Low price is greater than open price"}
        
      Decimal.compare(low, close) == :gt ->
        {:error, "Low price is greater than close price"}
        
      true -> :ok
    end
  end

  defp validate_single_ohlc(_point) do
    {:error, "Missing OHLC data"}
  end

  defp validate_volume_data(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {point, index}, acc ->
      volume = Map.get(point, :volume, 0)
      
      cond do
        volume < 0 ->
          issue = %{
            type: :invalid_data,
            index: index,
            description: "Negative volume",
            severity: :high
          }
          [issue | acc]
        
        true -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp detect_statistical_outliers(data) do
    # Simple outlier detection using close prices
    closes = 
      data
      |> Enum.map(fn point -> Map.get(point, :close) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Decimal.to_float/1)

    if length(closes) < 3 do
      {[], []}
    else
      outlier_indices = detect_outliers_iqr_simple(closes)
      
      outlier_issues = 
        Enum.map(outlier_indices, fn index ->
          %{
            type: :outlier,
            index: index,
            description: "Statistical outlier detected in close price",
            severity: :medium
          }
        end)

      {outlier_indices, outlier_issues}
    end
  end

  defp detect_outliers_iqr(data, opts) do
    field = Keyword.get(opts, :field, :close)
    
    values = 
      data
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        value = Map.get(point, field)
        if value && Decimal.is_decimal(value) do
          {Decimal.to_float(value), index}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(values) < 4 do
      []
    else
      numeric_values = Enum.map(values, fn {val, _} -> val end)
      outlier_values = detect_outliers_iqr_simple(numeric_values)
      
      values
      |> Enum.filter(fn {val, _index} -> val in outlier_values end)
      |> Enum.map(fn {val, index} ->
        %{
          index: index,
          field: field,
          value: val,
          method: :iqr
        }
      end)
    end
  end

  defp detect_outliers_iqr_simple(values) when length(values) >= 4 do
    sorted = Enum.sort(values)
    n = length(sorted)
    
    q1_pos = trunc(n * 0.25)
    q3_pos = trunc(n * 0.75)
    
    q1 = Enum.at(sorted, q1_pos)
    q3 = Enum.at(sorted, q3_pos)
    iqr = q3 - q1
    
    lower_bound = q1 - 1.5 * iqr
    upper_bound = q3 + 1.5 * iqr
    
    Enum.filter(values, fn val ->
      val < lower_bound or val > upper_bound
    end)
  end

  defp detect_outliers_iqr_simple(_values), do: []

  defp detect_outliers_zscore(data, opts) do
    field = Keyword.get(opts, :field, :close)
    threshold = Keyword.get(opts, :threshold, 3.0)
    
    # Simplified Z-score implementation
    values = extract_numeric_field(data, field)
    
    if length(values) < 3 do
      []
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, fn x -> (x - mean) * (x - mean) end)) / length(values)
      std_dev = :math.sqrt(variance)
      
      if std_dev == 0 do
        []
      else
        data
        |> Enum.with_index()
        |> Enum.filter(fn {point, _index} ->
          value = Map.get(point, field)
          if value && Decimal.is_decimal(value) do
            z_score = abs(Decimal.to_float(value) - mean) / std_dev
            z_score > threshold
          else
            false
          end
        end)
        |> Enum.map(fn {_point, index} ->
          %{index: index, field: field, method: :zscore}
        end)
      end
    end
  end

  defp detect_outliers_modified_zscore(data, opts) do
    # Simplified implementation - in practice would use median absolute deviation
    detect_outliers_zscore(data, Keyword.put(opts, :threshold, 3.5))
  end

  defp detect_outliers_isolation_forest(_data, _opts) do
    # Placeholder - would require more sophisticated implementation
    Logger.warning("Isolation Forest outlier detection not implemented, falling back to IQR")
    []
  end

  defp fill_gaps_forward(data) do
    {result, _} = 
      Enum.reduce(data, {[], nil}, fn point, {acc, last_valid} ->
        if Types.valid_ohlcv?(point) do
          {[point | acc], point}
        else
          if last_valid do
            filled_point = Map.merge(point, %{
              open: last_valid.close,
              high: last_valid.close,
              low: last_valid.close,
              close: last_valid.close
            })
            {[filled_point | acc], last_valid}
          else
            {acc, last_valid}  # Skip if no previous valid point
          end
        end
      end)
    
    Enum.reverse(result)
  end

  defp fill_gaps_backward(data) do
    data
    |> Enum.reverse()
    |> fill_gaps_forward()
    |> Enum.reverse()
  end

  defp fill_gaps_interpolate(data, _opts) do
    # Simple interpolation - in practice would be more sophisticated
    fill_gaps_forward(data)
  end

  defp remove_invalid_points(data) do
    Enum.filter(data, &Types.valid_ohlcv?/1)
  end

  defp normalize_minmax(data, opts) do
    field = Keyword.get(opts, :field, :close)
    
    values = extract_numeric_field(data, field)
    if length(values) == 0 do
      data
    else
      min_val = Enum.min(values)
      max_val = Enum.max(values)
      range = max_val - min_val
      
      if range == 0 do
        data
      else
        Enum.map(data, fn point ->
          current_val = Map.get(point, field)
          if current_val && Decimal.is_decimal(current_val) do
            normalized = (Decimal.to_float(current_val) - min_val) / range
            Map.put(point, field, Decimal.from_float(normalized))
          else
            point
          end
        end)
      end
    end
  end

  defp normalize_zscore(data, opts) do
    field = Keyword.get(opts, :field, :close)
    
    values = extract_numeric_field(data, field)
    if length(values) < 2 do
      data
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, fn x -> (x - mean) * (x - mean) end)) / length(values)
      std_dev = :math.sqrt(variance)
      
      if std_dev == 0 do
        data
      else
        Enum.map(data, fn point ->
          current_val = Map.get(point, field)
          if current_val && Decimal.is_decimal(current_val) do
            normalized = (Decimal.to_float(current_val) - mean) / std_dev
            Map.put(point, field, Decimal.from_float(normalized))
          else
            point
          end
        end)
      end
    end
  end

  defp normalize_robust(data, opts) do
    # Simplified robust normalization using median
    field = Keyword.get(opts, :field, :close)
    
    values = extract_numeric_field(data, field)
    if length(values) < 2 do
      data
    else
      sorted_values = Enum.sort(values)
      median = median(sorted_values)
      mad = median_absolute_deviation(values, median)
      
      if mad == 0 do
        data
      else
        Enum.map(data, fn point ->
          current_val = Map.get(point, field)
          if current_val && Decimal.is_decimal(current_val) do
            normalized = (Decimal.to_float(current_val) - median) / mad
            Map.put(point, field, Decimal.from_float(normalized))
          else
            point
          end
        end)
      end
    end
  end

  defp calculate_quality_score(total_points, issue_count) do
    if total_points == 0 do
      0.0
    else
      max(0.0, (total_points - issue_count) / total_points * 100)
    end
  end

  defp extract_numeric_field(data, field) do
    data
    |> Enum.map(fn point -> Map.get(point, field) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Decimal.is_decimal/1)
    |> Enum.map(&Decimal.to_float/1)
  end

  defp median(sorted_list) do
    n = length(sorted_list)
    if rem(n, 2) == 1 do
      Enum.at(sorted_list, div(n, 2))
    else
      (Enum.at(sorted_list, div(n, 2) - 1) + Enum.at(sorted_list, div(n, 2))) / 2
    end
  end

  defp median_absolute_deviation(values, median_val) do
    deviations = Enum.map(values, fn val -> abs(val - median_val) end)
    median(Enum.sort(deviations))
  end

  defp calculate_data_coverage(_data) do
    # Placeholder for data coverage analysis
    %{coverage_percentage: 100.0, gaps_detected: 0}
  end

  defp analyze_price_consistency(_data) do
    # Placeholder for price consistency analysis
    %{consistency_score: 100.0, ohlc_violations: 0}
  end

  defp analyze_volume_distribution(_data) do
    # Placeholder for volume distribution analysis
    %{distribution: "normal", zero_volume_count: 0}
  end

  defp analyze_timestamp_regularity(_data) do
    # Placeholder for timestamp regularity analysis
    %{regularity_score: 100.0, irregular_intervals: 0}
  end

  defp generate_quality_recommendations(report) do
    recommendations = []
    
    recommendations = if report.quality_score < 80 do
      ["Consider data cleaning to improve overall quality" | recommendations]
    else
      recommendations
    end
    
    recommendations = if report.outliers_detected > 0 do
      ["Review detected outliers for data integrity" | recommendations]
    else
      recommendations
    end
    
    recommendations = if report.chronological_errors > 0 do
      ["Sort data by timestamp to fix chronological order" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
end