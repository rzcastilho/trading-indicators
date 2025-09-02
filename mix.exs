defmodule TradingIndicators.MixProject do
  use Mix.Project

  def project do
    [
      app: :trading_indicators,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "TradingIndicators",
      source_url: "https://github.com/rzcastilho/trading_indicators",
      docs: docs(),
      
      # Testing and Quality Configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      
      # Static Analysis
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :race_conditions, :underspecs]
      ],
      
      # Type Checking
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TradingIndicators.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},
      {:benchee_json, "~> 1.0", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: :dev},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "A comprehensive Elixir library for trading indicators with consistent APIs, proper error handling, and extensible architecture."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/rzcastilho/trading_indicators"},
      maintainers: ["castilho"]
    ]
  end

  # Enhanced documentation configuration
  defp docs do
    [
      main: "TradingIndicators",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/indicators-guide.md",
        "guides/performance-guide.md",
        "guides/architecture.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Core": [TradingIndicators, TradingIndicators.Types],
        "Trend Indicators": [
          TradingIndicators.Trend,
          TradingIndicators.Trend.SMA,
          TradingIndicators.Trend.EMA,
          TradingIndicators.Trend.WMA,
          TradingIndicators.Trend.HMA,
          TradingIndicators.Trend.KAMA,
          TradingIndicators.Trend.MACD
        ],
        "Momentum Indicators": [
          TradingIndicators.Momentum,
          TradingIndicators.Momentum.RSI,
          TradingIndicators.Momentum.Stochastic,
          TradingIndicators.Momentum.CCI,
          TradingIndicators.Momentum.ROC,
          TradingIndicators.Momentum.WilliamsR
        ],
        "Volatility Indicators": [
          TradingIndicators.Volatility,
          TradingIndicators.Volatility.ATR,
          TradingIndicators.Volatility.BollingerBands,
          TradingIndicators.Volatility.StandardDeviation,
          TradingIndicators.Volatility.VolatilityIndex
        ],
        "Volume Indicators": [
          TradingIndicators.Volume,
          TradingIndicators.Volume.OBV,
          TradingIndicators.Volume.VWAP,
          TradingIndicators.Volume.AccumulationDistribution,
          TradingIndicators.Volume.ChaikinMoneyFlow
        ],
        "Utilities": [
          TradingIndicators.Utils,
          TradingIndicators.DataQuality,
          TradingIndicators.Pipeline,
          TradingIndicators.Streaming,
          TradingIndicators.Errors
        ]
      ]
    ]
  end

  # Environment-specific compilation paths
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
