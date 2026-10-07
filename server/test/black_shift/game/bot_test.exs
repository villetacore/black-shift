defmodule BlackShift.Game.BotTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game
  alias BlackShift.Game.{Bot, Combat}

  test "bot holds an empty relay and Warden heals instead of attacking while travelling" do
    s = versus_bot() |> place("human", 1.5, 12.5) |> place("bot", 33, 21.5)
    bot = BlackShift.Game.Bot.think(s, s.players["bot"])
    assert bot.input.forward == 0
    s = s |> place("bot", 12.5, 12.5) |> place("human", 1.5, 12.5)
    s = update_in(s.players["bot"], &%{&1 | class: "warden", hp: 50})
    bot = BlackShift.Game.Bot.think(s, s.players["bot"])
    assert bot.input.ability and not bot.input.sprint
  end

  test "bots cannot fire immediately after acquiring a player" do
    s = versus_bot() |> place("human", 10.5, 12.5) |> place("bot", 12.5, 12.5) |> steps(12)
    assert s.players["human"].hp == 100
    refute s.players["bot"].input.fire
  end

  test "turn speed is bounded and facing away does not snap onto target" do
    s =
      versus_bot()
      |> put_in([:players, "bot", :angle], 0.0)
      |> place("human", 10.5, 12.5)
      |> place("bot", 12.5, 12.5)

    assert abs(Game.step(s).players["bot"].angle) <= 0.12001
  end

  defp facing(s, id, angle), do: put_in(s, [:players, id, :angle], angle)

  test "bots only see what is in front of them, but hear gunfire behind them" do
    # The human stands 8 m behind a bot that faces away.
    s =
      versus_bot() |> place("human", 12.5, 14.5) |> place("bot", 20.5, 14.5) |> facing("bot", 0.0)

    bot = Bot.think(s, s.players["bot"])
    assert bot.ai_target == nil

    loud = put_in(s, [:players, "human", :last_shot], s.tick)
    bot = Bot.think(loud, loud.players["bot"])
    assert bot.ai_memory.x == 12.5
    # Turning towards the noise, at the bounded turn rate.
    assert bot.input.angle > 0.11 or bot.input.angle < -0.11

    seen = facing(s, "bot", :math.pi())
    assert Bot.think(seen, seen.players["bot"]).ai_target == "human"
  end

  test "bots learn where damage came from" do
    s =
      versus_bot() |> place("human", 12.5, 14.5) |> place("bot", 20.5, 14.5) |> facing("bot", 0.0)

    s = Combat.hurt_player(s, "bot", 10, "human", s.players["human"])
    bot = Bot.think(s, s.players["bot"])
    assert bot.ai_memory.x == 12.5
  end

  test "bots reload an empty magazine and strafe in a close fight" do
    s = versus_bot() |> place("human", 12.5, 14.5) |> place("bot", 20.5, 14.5)
    s = put_in(s, [:players, "bot", :ammo], 0)
    assert Bot.think(s, s.players["bot"]).input.reload

    s = put_in(s, [:players, "bot", :ammo], 25)
    bot = Bot.think(s, s.players["bot"])
    # Facing the target along -x, strafing is mostly sideways input.
    assert abs(bot.input.strafe) > abs(bot.input.forward)
  end

  test "aim starts loose and settles while a target stays in view" do
    s = versus_bot() |> place("human", 12.5, 14.5) |> place("bot", 20.5, 14.5)
    s = put_in(s, [:players, "human", :protected_until], 10_000)
    first = Game.step(s).players["bot"].ai_error
    later = steps(s, 30).players["bot"].ai_error
    assert first > 0.1
    assert later < first / 3
  end

  test "smoothed routes cut grid corners but keep every floor change" do
    start = {4.5, 22.7, 0.0}
    goal = BlackShift.Game.Objective.current(%{tick: 3600})
    path = BlackShift.World.Navigation.path(start, {goal.x, goal.y, goal.z})
    smooth = BlackShift.World.Navigation.smooth(start, path)
    assert length(smooth) < length(path) / 2
    assert List.last(smooth) == List.last(path)
  end
end
