alias BlackShift.Game
alias BlackShift.Game.Rules

results =
  for variant <- 0..4 do
    players =
      for i <- 0..5 do
        %{
          id: "bot-#{variant}-#{i}",
          bot: true,
          class: if(rem(i + variant, 3) == 0, do: "warden", else: "ranger")
        }
      end

    initial = %{Game.new("benchmark-#{variant}", players) | tick: 0}

    {last, first, captures, changes} =
      Enum.reduce_while(1..Rules.match_ticks(), {initial, nil, 0, 0}, fn _,
                                                                         {s, first, captures,
                                                                          changes} ->
        next = Game.step(s)
        secured = next.relay >= 0 and next.relay != s.relay
        first = if secured and first == nil, do: Rules.seconds(next.tick), else: first
        captures = captures + if(secured, do: 1, else: 0)
        changes = changes + if(secured and s.relay >= 0, do: 1, else: 0)
        result = {next, first, captures, changes}
        if next.over, do: {:halt, result}, else: {:cont, result}
      end)

    [a, b] = last.score

    result = %{
      match: variant,
      duration: Rules.seconds(last.tick),
      first_capture: first,
      captures: captures,
      ownership_changes: changes,
      timed_out: last.tick >= Rules.match_ticks(),
      score: last.score,
      score_gap: abs(a - b),
      kills: Enum.sum(Enum.map(last.players, fn {_, p} -> p.kills end))
    }

    IO.puts(:stderr, "Completed match #{variant}: #{inspect(result)}")
    result
  end

IO.puts(IO.iodata_to_binary(:json.encode(%{matches: results})))
