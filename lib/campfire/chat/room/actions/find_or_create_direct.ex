defmodule Campfire.Chat.Room.Actions.FindOrCreateDirect do
  @moduledoc """
  Finds the direct room for exactly these users (plus the actor), or creates it. Safe against
  two requests creating the same room at once.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Changeset
  alias Campfire.Chat.Room

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    user_ids = Room.existing_user_ids([actor.id | input.arguments.user_ids])
    key = Room.direct_key(user_ids)

    case find_direct(key) do
      %Room{} = room ->
        {:ok, room}

      nil ->
        # The action's policy already checked the actor is active; `:create_direct` has no
        # policy of its own.
        Room
        |> Changeset.for_create(:create_direct, %{user_ids: user_ids}, actor: actor)
        |> Ash.create(authorize?: false)
        |> case do
          {:ok, room} ->
            {:ok, room}

          # Lost a race with another request creating the same room.
          {:error, error} ->
            case find_direct(key) do
              %Room{} = room -> {:ok, room}
              nil -> {:error, error}
            end
        end
    end
  end

  defp find_direct(key) do
    Room
    |> Ash.Query.filter(direct_key == ^key)
    |> Ash.read_one!(authorize?: false)
  end
end
