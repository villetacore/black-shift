defmodule BlackShift.Application do
  @moduledoc """
  Supervision tree (`rest_for_one`, so a restarted process also restarts
  everything that depends on it):

      Persistence.Store            Mnesia schema and table lifecycle
      Match.Supervisor             DynamicSupervisor of Match.Server, one per live match
      Match.Matchmaker             FIFO queue of waiting sessions
      Network.SessionSupervisor    DynamicSupervisor of Network.Session, one per connection
      Network.Listener             listening socket and acceptor
  """
  use Application

  @impl true
  def start(_type, _args) do
    BlackShift.World.Navigation.warmup()

    children = [
      BlackShift.Persistence.Store,
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: BlackShift.Match.Supervisor,
       max_children: Application.fetch_env!(:blackshift, :max_matches)},
      BlackShift.Match.Matchmaker,
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: BlackShift.Network.SessionSupervisor,
       max_children: Application.fetch_env!(:blackshift, :max_sessions)},
      BlackShift.Network.Listener
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: BlackShift.Supervisor)
  end
end
