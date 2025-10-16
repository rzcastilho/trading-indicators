# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TradingIndicators** is a comprehensive Elixir library for technical analysis with 22 trading indicators across 4 categories. Built with Decimal precision for financial accuracy, featuring consistent APIs, robust error handling, and real-time streaming support.

## Common Development Commands

### Testing
```bash
# Run all tests (excludes integration, property, and performance tests by default)
mix test

# Run with coverage report
mix test --cover

# Run specific test file
mix test test/path/to/test_file.exs

# Run tests at specific line
mix test test/path/to/test_file.exs:123

# Run with specific seed for reproducibility
mix test --seed 0

# Include tagged tests
mix test --include integration    # Integration tests
mix test --include property       # Property-based tests
mix test --include property test/property_tests/trend_property_test.exs
mix test --include performance    # Performance tests
```

### Code Quality
```bash
# Format code (100 character line length)
mix format

# Run Credo linter
mix credo

# Run Dialyzer type checker
mix dialyzer

# Run Sobelow security analysis
mix sobelow

# Run comprehensive checks
mix check
```

### Documentation
```bash
# Generate documentation
mix docs

# Open documentation
open doc/index.html
```

### Dependencies
```bash
# Install dependencies
mix deps.get

# Update dependencies
mix deps.update --all
```

## Architecture

### Core Behavior Contract

All indicators implement `TradingIndicators.Behaviour` which defines:
- `calculate/2` - Batch processing of historical data
- `validate_params/1` - Parameter validation
- `required_periods/0` - Minimum data requirements
- `parameter_metadata/0` - Returns structured metadata about configurable parameters
- `init_state/1` and `update_state/2` - Optional streaming support

### Category Module Structure

The library is organized into 4 category modules, each following the same pattern:
- **TradingIndicators.Trend** - 6 trend indicators (SMA, EMA, WMA, HMA, KAMA, MACD)
- **TradingIndicators.Momentum** - 6 momentum oscillators (RSI, Stochastic, Williams %R, CCI, ROC, Momentum)
- **TradingIndicators.Volatility** - 4 volatility measures (Bollinger Bands, ATR, Standard Deviation, Volatility Index)
- **TradingIndicators.Volume** - 4 volume indicators (OBV, VWAP, A/D Line, CMF)

Each category module provides:
- `available_indicators/0` - List all indicators in category
- `calculate/3` - Unified calculation interface
- Convenience functions for each indicator (e.g., `sma/2`, `ema/2`)
- Streaming support via `init_stream/2`, `update_stream/2`, `reset_stream/1`, `has_sufficient_data?/1`

### Advanced Modules (Phase 6)

- **TradingIndicators.Streaming** - Enhanced real-time streaming with batch processing, stream composition, state persistence
- **TradingIndicators.Pipeline** - Multi-indicator workflows with dependency management and parallel execution
- **TradingIndicators.Performance** - Benchmarking, memory profiling, caching with multiple eviction policies
- **TradingIndicators.DataQuality** - Data validation, outlier detection, gap filling, quality scoring
- **TradingIndicators.Security** - Input validation and sanitization
- **TradingIndicators.ParamValidator** - Automatic parameter validation using metadata constraints

### Data Types

All indicators work with standardized OHLCV data:
```elixir
%{
  open: Decimal.new("100.0"),
  high: Decimal.new("105.0"),
  low: Decimal.new("99.0"),
  close: Decimal.new("103.0"),
  volume: 1000,  # Required for volume indicators
  timestamp: ~U[2024-01-01 09:30:00Z]
}
```

Results follow a consistent format:
```elixir
%{
  value: Decimal.t(),           # The calculated indicator value
  timestamp: DateTime.t(),      # When this value applies
  metadata: %{                  # Indicator-specific metadata
    indicator: "SMA",
    period: 20,
    source: :close,
    signal: :neutral            # :bullish, :bearish, :neutral
    # ... additional metadata varies by indicator
  }
}
```

### Key Design Patterns

1. **Decimal Precision**: All numeric values use `Decimal` library to avoid floating-point errors
2. **Error Types**: Specific exception structs in `TradingIndicators.Errors`:
   - `InsufficientData` - Not enough data points
   - `InvalidParams` - Invalid parameters
   - `InvalidDataFormat` - Malformed input data
   - `CalculationError` - Mathematical calculation errors
3. **Streaming State**: Each indicator maintains internal state for incremental updates
4. **Type Safety**: Comprehensive `@spec` annotations throughout
5. **Utilities**: Common functions in `TradingIndicators.Utils` for data extraction and manipulation
6. **Parameter Introspection**: All indicators provide structured metadata through `parameter_metadata/0` callback

### Parameter Introspection System

All indicators implement the `parameter_metadata/0` callback which returns structured metadata about their configurable parameters. This enables:

- **API Introspection**: Discover parameters programmatically without reading documentation
- **Dynamic UI Generation**: Build configuration interfaces automatically
- **Automatic Validation**: Validate parameters using `TradingIndicators.ParamValidator`
- **Documentation Generation**: Auto-generate parameter tables and API docs

#### ParamMetadata Structure

Each parameter is described using `TradingIndicators.Types.ParamMetadata` struct with:
- `:name` - Parameter name as atom (required)
- `:type` - Parameter type: `:integer`, `:float`, `:string`, or `:atom` (required)
- `:default` - Default value (required)
- `:required` - Whether parameter is required (boolean, required)
- `:min` - Minimum value for numeric parameters (optional)
- `:max` - Maximum value for numeric parameters (optional)
- `:options` - List of valid values for enum-like parameters (optional)
- `:description` - Human-readable description (optional)

#### Usage Example

```elixir
# Get parameter metadata for any indicator
metadata = TradingIndicators.Momentum.RSI.parameter_metadata()

# Returns list of ParamMetadata structs:
# [
#   %ParamMetadata{name: :period, type: :integer, default: 14, min: 1, ...},
#   %ParamMetadata{name: :source, type: :atom, options: [:open, :high, :low, :close], ...},
#   ...
# ]

# Automatic validation using metadata
params = [period: 14, source: :close]
:ok = TradingIndicators.ParamValidator.validate_params(params, metadata)
```

#### Implementation Notes

- Indicators without parameters (e.g., OBV, A/D) return empty list `[]`
- Use module attributes (`@default_period`) for default values to maintain DRY principle
- ParamValidator provides automatic type, range, and option validation
- Metadata must accurately reflect actual parameter behavior and validation logic

## Test Structure

- **Unit Tests**: `test/trading_indicators/` - organized by category (trend, momentum, volatility, volume)
- **Integration Tests**: `test/integration_tests/` - cross-module integration scenarios
- **Property Tests**: `test/property_tests/` - property-based testing with StreamData
- **Test Support**: `test/support/` - shared helpers, generators, and utilities

Test configuration in `test/test_helper.exs`:
- Tags: `:integration`, `:property`, `:performance` (excluded by default)
- Timeout: 60 seconds for comprehensive tests
- Parallel execution: 2x CPU cores

## Adding New Indicators

When implementing a new indicator:

1. Create module under appropriate category (e.g., `lib/trading_indicators/trend/my_indicator.ex`)
2. Implement `TradingIndicators.Behaviour` callbacks:
   - `calculate/2` - Main calculation logic
   - `validate_params/1` - Parameter validation
   - `required_periods/0` - Minimum data requirements
   - `parameter_metadata/0` - Parameter metadata (required)
   - `init_state/1` and `update_state/2` - Optional streaming support
3. Implement `parameter_metadata/0` callback:
   - Return list of `TradingIndicators.Types.ParamMetadata` structs
   - Include all configurable parameters with accurate metadata
   - Use module attributes for default values (DRY principle)
   - Return empty list `[]` if indicator has no parameters
   - Ensure metadata matches validation logic in `validate_params/1`
4. Add comprehensive `@moduledoc` with mathematical formula and usage examples
5. Include `@spec` type annotations for all public functions
6. Update category module to include new indicator
7. Write comprehensive tests including:
   - Basic calculation tests
   - Edge cases (empty data, insufficient data, invalid params)
   - Parameter metadata tests (verify structure and values)
   - Streaming tests if applicable
   - Doctests in module documentation
8. Update documentation guides if introducing new patterns

## Code Style

- Line length: 100 characters (enforced by formatter)
- Follow Elixir naming conventions
- Use `with` for multiple operations that can fail
- Pattern match on `{:ok, result}` and `{:error, reason}` tuples
- Prefer explicit over implicit
- Document all public functions with examples
- Include mathematical formulas in indicator documentation

## Development Workflow

1. Make changes to code
2. Run `mix format` to format
3. Run `mix test` to verify tests pass
4. Run `mix credo` for linting issues
5. Run `mix dialyzer` for type checking (first run builds PLT, takes time)
6. Update documentation if changing public APIs
7. Commit with descriptive messages

## Performance Considerations

- Use streaming mode for real-time applications (avoids recalculation)
- Batch mode optimized for historical data analysis
- Pipeline module enables parallel indicator execution
- Enable caching via `TradingIndicators.Performance.enable_caching/1` for repeated calculations
- Streaming batch processing achieves >1000 updates/second per indicator
- Validate data quality before computationally expensive calculations

## Dependencies

Key dependencies:
- **decimal** (~> 2.0) - Financial precision arithmetic
- **ex_doc** (~> 0.30) - Documentation generation
- **dialyxir** (~> 1.3) - Static type analysis
- **credo** (~> 1.7) - Code linting
- **benchee** (~> 1.1) - Performance benchmarking
- **stream_data** (~> 1.0) - Property-based testing
- **excoveralls** (~> 0.18) - Test coverage
- **sobelow** (~> 0.13) - Security analysis
