defmodule BlackShift.Game.Rules do
  @moduledoc "Match-wide timing and victory rules. Durations are in simulation ticks."

  @tick_rate 20
  @match_ticks 5 * 60 * @tick_rate
  @winning_score 200

  def tick_rate, do: @tick_rate
  def match_ticks, do: @match_ticks
  def winning_score, do: @winning_score

  @doc "Converts a tick count to seconds."
  def seconds(ticks), do: ticks / @tick_rate
end
