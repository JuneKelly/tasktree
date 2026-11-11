# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tasktree,
  ecto_repos: [Tasktree.Repo],
  generators: [timestamp_type: :utc_datetime],
  workflow_path: Path.expand("../priv/workflow.exs", __DIR__)

# Configure the endpoint
config :tasktree, TasktreeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TasktreeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tasktree.PubSub,
  live_view: [signing_salt: "7lwoCObk"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
