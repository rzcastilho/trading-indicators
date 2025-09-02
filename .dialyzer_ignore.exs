# Dialyzer configuration for static analysis and type checking

[
  # Dialyzer flags for comprehensive analysis
  {":dialyzer",
   [
     # Analysis flags
     flags: [
       :error_handling,     # Check error handling
       :race_conditions,    # Check for race conditions  
       :underspecs,        # Warn about underspecified functions
       :unknown,           # Warn about unknown functions
       :unmatched_returns, # Warn about unused return values
       :overspecs,         # Warn about overspecified functions
       :specdiffs,         # Warn about spec mismatches
       :no_improper_lists, # Don't allow improper lists
       :no_undefined_callbacks  # Warn about undefined callbacks
     ],
     
     # PLT configuration
     plt_add_deps: :app_tree,
     plt_add_apps: [:kernel, :stdlib, :erts, :crypto, :decimal],
     plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
     
     # Files to analyze
     paths: ["_build/dev/lib/trading_indicators/ebin"],
     
     # Warnings to ignore (these are typically acceptable)
     ignore_warnings: ".dialyzer_ignore",
     
     # Format for warnings
     format: :short,
     
     # Remove PLT on compile
     plt_remove: false,
     
     # Check PLT health
     check_plt: true
   ]},
  
  # Additional configuration for OTP applications
  {":kernel", []},
  {":stdlib", []},
  {":crypto", []},
  {":decimal", []}
]