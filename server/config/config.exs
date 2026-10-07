import Config

config :blackshift,
  port: 7777,
  bind: {127, 0, 0, 1},
  db_dir: "data/mnesia",
  max_matches: 64,
  max_sessions: 256

config :logger, :console, format: "$level $message\n"

if config_env() == :test do
  config :blackshift,
    port: 0,
    db_dir: Path.join(System.tmp_dir!(), "blackshift-test-#{System.unique_integer([:positive])}")
end
