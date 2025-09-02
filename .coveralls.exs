# Coveralls configuration for comprehensive test coverage analysis

[
  # Coverage threshold - aim for >95%
  minimum_coverage: 95.0,
  
  # Output directory for HTML reports
  output_dir: "cover/",
  
  # Files to include/exclude from coverage
  skip_files: [
    # Test support files
    "test/support/",
    
    # Generated files
    "_build/",
    "deps/",
    
    # Mix tasks
    "lib/mix/tasks/",
    
    # Application file (minimal logic)
    "lib/trading_indicators/application.ex"
  ],
  
  # Coverage reporting options
  html_output: "cover",
  xml_output: "cover/coverage.xml",
  json_output: "cover/coverage.json",
  
  # Terminal output customization
  terminal_options: [
    file_column_width: 40,
    print_summary: true,
    print_files: true
  ],
  
  # Treat as failure if minimum coverage not met
  treat_no_relevant_lines_as_covered: true,
  
  # Custom coverage goals per module type
  per_module: %{
    "TradingIndicators.Trend" => %{minimum_coverage: 95.0},
    "TradingIndicators.Momentum" => %{minimum_coverage: 95.0},
    "TradingIndicators.Volatility" => %{minimum_coverage: 95.0},
    "TradingIndicators.Volume" => %{minimum_coverage: 95.0},
    "TradingIndicators.Utils" => %{minimum_coverage: 98.0},
    "TradingIndicators.DataQuality" => %{minimum_coverage: 98.0},
    "TradingIndicators.Pipeline" => %{minimum_coverage: 95.0},
    "TradingIndicators.Streaming" => %{minimum_coverage: 95.0}
  },
  
  # Stop on first coverage failure
  halt_on_failure: true
]