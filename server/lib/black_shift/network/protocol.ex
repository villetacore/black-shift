defmodule BlackShift.Network.Protocol do
  @moduledoc """
  Wire protocol v1: UTF-8 JSON Lines over TCP. See `docs/protocol.md`.

  Incoming JSON keys stay strings; network data never creates atoms.
  """

  @version 1
  @max_line_bytes 4096
  @default_name "Operator"
  @max_name_length 20
  @classes ["ranger", "warden"]
  @modes ["online", "practice"]

  def version, do: @version
  def max_line_bytes, do: @max_line_bytes

  @doc "Encodes one message as a newline-terminated JSON line."
  def encode(message), do: [:json.encode(message), "\n"]

  @doc "Decodes one line into a JSON object."
  def decode(bytes) do
    case :json.decode(bytes) do
      message when is_map(message) -> {:ok, message}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc "Validates a `join` message into `{:ok, mode, %{name: ..., class: ...}}`."
  def parse_join(%{"version" => @version, "mode" => mode} = message) when mode in @modes,
    do: {:ok, mode, %{name: sanitize_name(message["name"]), class: parse_class(message["class"])}}

  def parse_join(_), do: {:error, "Protocol #{@version} and valid mode required"}

  defp sanitize_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[^\p{L}\p{N} _-]/u, "")
    |> String.trim()
    |> String.slice(0, @max_name_length)
    |> case do
      "" -> @default_name
      name -> name
    end
  end

  defp sanitize_name(_), do: @default_name

  defp parse_class(class) when class in @classes, do: class
  defp parse_class(_), do: "ranger"

  # Server -> client messages.

  def hello(id), do: %{type: "hello", version: @version, id: id}
  def pong, do: %{type: "pong"}
  def error(message), do: %{type: "error", message: message}
  def queue(waiting, needed), do: %{type: "queue", waiting: waiting, needed: needed}

  def start(match, player_id, team, map, tick_rate),
    do: %{type: "start", match: match, id: player_id, team: team, map: map, tick_rate: tick_rate}

  def result(match, winner), do: %{type: "result", winner: winner, match: match, saved: true}
end
