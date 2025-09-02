# Ex Check configuration for coordinated quality analysis

[
  ## Tools configuration
  
  # Static Analysis Tools
  tools: [
    # Code compilation check
    {:compiler, "mix compile --warnings-as-errors --force", [env: %{"MIX_ENV" => "test"}]},
    
    # Code formatting check  
    {:formatter, "mix format --check-formatted"},
    
    # Static code analysis
    {:credo, "mix credo --strict"},
    
    # Type checking with Dialyzer
    {:dialyzer, "mix dialyzer --format short", [env: %{"MIX_ENV" => "dev"}]},
    
    # Security analysis
    {:sobelow, "mix sobelow --config"},
    
    # Documentation quality
    {:doctor, "mix doctor --full"},
    
    # Test suite
    {:ex_unit, "mix test --warnings-as-errors", [env: %{"MIX_ENV" => "test"}]},
    
    # Test coverage
    {:coverage, "mix coveralls", [env: %{"MIX_ENV" => "test"}]},
    
    # Dependency audit
    {:deps_audit, "mix deps.audit"},
    
    # Unused dependencies
    {:deps_unlock, "mix deps.unlock --check-unused"},
    
    # Property-based tests (when enabled)
    {:property_tests, "mix test --include property", 
     [env: %{"MIX_ENV" => "test"}, enabled: false]},
    
    # Integration tests (when enabled)
    {:integration_tests, "mix test --include integration",
     [env: %{"MIX_ENV" => "test"}, enabled: false]},
     
    # Benchmark tests (when enabled)
    {:benchmark_tests, "mix test --include benchmark",
     [env: %{"MIX_ENV" => "test"}, enabled: false]}
  ],
  
  ## Parallel execution configuration
  parallel: true,
  
  ## Tool-specific configuration
  fix: true,  # Allow tools to fix issues when possible
  
  ## Retry configuration
  retry: false,
  
  ## Skipped tools (can be enabled selectively)
  skipped: [],
  
  ## Custom tool definitions
  custom_commands: [
    # Full quality check including all test types
    {"quality:full", [
      "mix compile --warnings-as-errors --force",
      "mix format --check-formatted", 
      "mix credo --strict",
      "mix dialyzer --format short",
      "mix sobelow --config",
      "mix doctor --full",
      "mix coveralls.html",
      "mix test --include property --include integration"
    ]},
    
    # Quick quality check (essential tools only)
    {"quality:quick", [
      "mix compile --warnings-as-errors",
      "mix format --check-formatted",
      "mix credo",
      "mix test"
    ]},
    
    # Performance analysis
    {"performance", [
      "mix test --include benchmark",
      "mix run -e \"TradingIndicators.TestSupport.BenchmarkHelpers.comparative_benchmark()\"" 
    ]},
    
    # Security analysis
    {"security", [
      "mix sobelow --config",
      "mix deps.audit",
      "mix deps.unlock --check-unused"
    ]},
    
    # Documentation generation and validation
    {"docs", [
      "mix doctor --full",
      "mix docs",
      "mix test --include doctests"
    ]}
  ]
]