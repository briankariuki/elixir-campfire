defmodule Campfire.Chat.Room.Validations.NotDirect do
  @moduledoc "A direct room can't be turned into an open or closed room."

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if changeset.data.kind == :direct do
      {:error, field: :kind, message: "can't be changed for a direct room"}
    else
      :ok
    end
  end
end
