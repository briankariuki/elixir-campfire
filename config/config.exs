# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_oban, pro?: false

config :campfire, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  # embeds: link previews fetch other sites, so they get their own lane and can't hold up
  # webhooks or ban cleanup (and vice versa)
  queues: [default: 10, webhooks: 10, embeds: 5],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: Campfire.Repo,
  cron: [crontab: []]

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  infer_generic_action_reactors?: false,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :rate_limit,
        :admin,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

# AshAdmin acts as the signed-in administrator (see CampfireWeb.AdminActorPlug)
config :ash_admin, actor_plug: CampfireWeb.AdminActorPlug

config :campfire,
  ecto_repos: [Campfire.Repo],
  ash_domains: [Campfire.Accounts, Campfire.Chat],
  generators: [timestamp_type: :utc_datetime, binary_id: false]

# Where uploaded files (avatars, logos, attachments) are stored on disk.
config :campfire, :uploads_dir, Path.expand("../priv/uploads", __DIR__)

# Renders a message's body as HTML for webhook payloads (same as the bot API). Wired here so the
# domain (Campfire.Webhooks) doesn't depend on the web layer.
config :campfire, :message_html, {CampfireWeb.MessageBody, :to_html_string}

# Extra Req options for webhook deliveries (tests plug in Req.Test here).
config :campfire, :webhook_req_options, []

# Extra Req options for link preview fetches (tests plug in Req.Test here).
config :campfire, :opengraph_req_options, []

# Configure the endpoint
config :campfire, CampfireWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CampfireWeb.ErrorHTML, json: CampfireWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Campfire.PubSub,
  live_view: [signing_salt: "9PF9zgpo"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  campfire: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  # Campfire's original plain CSS, bundled (just @import inlining) by esbuild. No Tailwind.
  campfire_css: [
    args:
      ~w(css/app.css --bundle --outdir=../priv/static/assets/css --external:/images/* --external:/sounds/*),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Elixir's built-in JSON (1.18+) for Phoenix: websocket frames, the JSON parser, controller `json/2`.
# Faster than Jason for the LiveView diffs (bench/TUNING.md). Jason stays a dependency for Ash, Oban and Req.
config :phoenix, :json_library, JSON

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
