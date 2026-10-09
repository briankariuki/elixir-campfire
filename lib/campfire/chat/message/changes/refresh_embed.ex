defmodule Campfire.Chat.Message.Changes.RefreshEmbed do
  @moduledoc """
  On edit: clears the embed when the message's first link changes (or disappears), so the old
  preview isn't shown for the new link while the `:fetch_embed` job (enqueued by
  `Campfire.Chat.Message.Notifiers.EnqueueEmbed`) fetches the new one.
  """

  use Ash.Resource.Change

  alias Campfire.Chat.Opengraph

  @impl true
  def change(changeset, _opts, _context) do
    old_url = Opengraph.first_url(changeset.data.body)
    new_url = Opengraph.first_url(Ash.Changeset.get_attribute(changeset, :body))

    if old_url == new_url do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, :embed, nil)
    end
  end
end
