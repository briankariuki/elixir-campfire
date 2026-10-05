defmodule Campfire.MixProject do
  use Mix.Project

  def project do
    [
      app: :campfire,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      usage_rules: usage_rules()
    ]
  end

  # `mix usage_rules.sync` keeps AGENTS.md and .claude/skills in step with the deps' usage rules.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        :usage_rules,
        "phoenix:elixir",
        "phoenix:phoenix",
        "phoenix:html",
        "phoenix:liveview",
        :igniter,
        {:ash, link: :markdown},
        {:ash_postgres, link: :markdown},
        {:ash_phoenix, link: :markdown}
      ],
      skills: [
        location: ".claude/skills",
        build: [
          "ash-framework": [
            description:
              "Use when writing or reviewing Ash code in this project: resources, actions, policies, queries, calculations, AshPostgres migrations and AshPhoenix forms.",
            usage_rules: [
              :ash,
              "ash:all",
              :ash_postgres,
              "ash_postgres:all",
              :ash_phoenix,
              "ash_phoenix:all"
            ]
          ],
          "phoenix-framework": [
            description:
              "Use when working on the Phoenix web layer: controllers, LiveViews, HEEx templates and JS hooks.",
            usage_rules: ["phoenix:all"]
          ]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Campfire.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:hammer, "~> 7.0"},
      {:ash_rate_limiter, "~> 2.0"},
      {:oban, "~> 2.0"},
      {:ash_oban, "~> 0.9"},
      {:ash_admin, "~> 1.0"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash, "~> 3.0"},
      # SAT solver required by Ash policies
      {:picosat_elixir, "~> 0.2"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.0"},
      {:req, "~> 0.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild campfire", "esbuild campfire_css"],
      "assets.deploy": [
        "esbuild campfire --minify",
        "esbuild campfire_css --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
