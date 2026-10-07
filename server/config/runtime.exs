import Config

if config_env() != :test do
  {port, ""} = Integer.parse(System.get_env("BS_PORT", "7777"))
  if port < 0 or port > 65535, do: raise("BS_PORT must be 0..65535")
  {:ok, bind} = :inet.parse_address(String.to_charlist(System.get_env("BS_BIND", "127.0.0.1")))

  config :blackshift,
    port: port,
    bind: bind,
    db_dir: Path.expand(System.get_env("BS_DB_DIR", "data/mnesia"))
end
