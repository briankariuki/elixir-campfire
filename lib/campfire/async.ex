defmodule Campfire.Async do
  @moduledoc """
  Runs background work (webhook deliveries, ban cleanup) under `Campfire.TaskSupervisor`.
  With `config :campfire, :async_tasks, false` (the test env) the work runs inline.
  """

  def run(fun) when is_function(fun, 0) do
    if Application.get_env(:campfire, :async_tasks, true) do
      {:ok, _pid} = Task.Supervisor.start_child(Campfire.TaskSupervisor, fun)
      :ok
    else
      fun.()
      :ok
    end
  end
end
