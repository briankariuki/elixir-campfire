defmodule Campfire.Chat.Message.Validations.HasContent do
  @moduledoc "A message needs a non-blank body or an attachment."

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    body = Changeset.get_attribute(changeset, :body)
    attachment_key = Changeset.get_attribute(changeset, :attachment_key)

    if (is_binary(body) and String.trim(body) != "") or is_binary(attachment_key) do
      :ok
    else
      {:error, field: :body, message: "can't be blank"}
    end
  end
end
