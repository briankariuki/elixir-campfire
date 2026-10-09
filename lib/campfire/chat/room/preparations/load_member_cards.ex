defmodule Campfire.Chat.Room.Preparations.LoadMemberCards do
  @moduledoc """
  Loads `:users` with only what a room page uses to show a member: `id`, `name` (mentions, the
  `@` menu, typing, direct room names) and `avatar_key` (avatar URLs). Every other attribute stays
  `%Ash.NotLoaded{}`, so a connected room page doesn't hold the emails, bios and tokens of every
  member (an open room's members are everyone).

  The load goes through the user read policy (an actor is required, like any `:users` load).
  """

  use Ash.Resource.Preparation

  alias Campfire.Accounts.User

  @fields [:id, :name, :avatar_key]

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.load(query, users: Ash.Query.select(User, @fields))
  end
end
