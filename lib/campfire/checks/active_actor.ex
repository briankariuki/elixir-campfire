defmodule Campfire.Checks.ActiveActor do
  @moduledoc "The actor is an active user."

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an active user"

  @impl true
  def match?(%{status: :active}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
