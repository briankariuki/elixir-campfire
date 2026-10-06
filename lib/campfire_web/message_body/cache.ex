defmodule CampfireWeb.MessageBody.Cache do
  @moduledoc """
  A render cache for message body HTML (`CampfireWeb.MessageBody.cached_html/3`).

  Every connected room LiveView renders each new or edited message itself, so N viewers cost N
  identical renders. The rendered HTML is kept in a named, public ETS table
  (`read_concurrency: true`), so it is computed once per message version and read by all viewers
  without going through a process.

  ## Entries

  `{key, html, seq}`: `html` is the rendered binary, `seq` a monotonic integer taken at insertion
  (the eviction order). The key is built by `MessageBody.cached_html/3`: it changes whenever the
  output would (message id and `updated_at`, `live?`, and a hash of the body and of the mentioned
  users' id, name and avatar), so nothing is ever invalidated: a changed message or user simply
  misses, and the stale entry ages out.

  ## Bounding memory

  The table is capped at `max_entries` (default #{10_000}, `config :campfire, #{inspect(__MODULE__)},
  max_entries: n`). After each insert the owner process is told (`cast`, so the caller doesn't
  wait); when the table is over the cap it drops the oldest entries (by `seq`) until 80% of the cap
  is left. That is one `select` of the sequence numbers and one `select_delete` every ~2000
  inserts, off the callers' path. The table is owned by this small GenServer, so it lives as long as
  the supervision tree does; if the process is down, `fetch/3` just renders without caching.

  Set `config :campfire, #{inspect(__MODULE__)}, enabled: false` to render uncached (read on every
  call).

  ## Telemetry

  `[:campfire, :message_body_cache, :hit | :miss]`, with `%{key: key}` as metadata.
  """

  use GenServer

  @default_max 10_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  The cached HTML for `key`, else `render.()` (returning a binary) stored under it. `table` is the
  cache's name.
  """
  def fetch(key, render, table \\ __MODULE__) when is_function(render, 0) do
    cond do
      not enabled?() or :ets.whereis(table) == :undefined ->
        render.()

      true ->
        case :ets.lookup(table, key) do
          [{^key, html, _seq}] ->
            :telemetry.execute([:campfire, :message_body_cache, :hit], %{}, %{key: key})
            html

          [] ->
            html = render.()
            :ets.insert(table, {key, html, :erlang.unique_integer([:monotonic])})
            :telemetry.execute([:campfire, :message_body_cache, :miss], %{}, %{key: key})
            GenServer.cast(table, :inserted)
            html
        end
    end
  end

  @doc "The number of entries."
  def size(table \\ __MODULE__) do
    case :ets.info(table, :size) do
      :undefined -> 0
      size -> size
    end
  end

  defp enabled? do
    :campfire |> Application.get_env(__MODULE__, []) |> Keyword.get(:enabled, true)
  end

  ## Server

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :name, __MODULE__)

    max =
      Keyword.get_lazy(opts, :max_entries, fn ->
        :campfire
        |> Application.get_env(__MODULE__, [])
        |> Keyword.get(:max_entries, @default_max)
      end)

    :ets.new(table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])

    {:ok, %{table: table, max: max}}
  end

  @impl true
  def handle_cast(:inserted, %{table: table, max: max} = state) do
    if :ets.info(table, :size) > max, do: evict(table, max)
    {:noreply, state}
  end

  # Drops the oldest entries, down to 80% of the cap
  defp evict(table, max) do
    seqs = :ets.select(table, [{{:_, :_, :"$1"}, [], [:"$1"]}])
    drop = length(seqs) - div(max * 8, 10)

    if drop > 0 do
      threshold = seqs |> Enum.sort() |> Enum.at(drop - 1)
      :ets.select_delete(table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", threshold}], [true]}])
    end
  end
end
