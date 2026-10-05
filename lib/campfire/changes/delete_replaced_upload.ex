defmodule Campfire.Changes.DeleteReplacedUpload do
  @moduledoc """
  When an update changes an upload key attribute (e.g. `:avatar_key`), deletes the old file
  from `Campfire.Uploads` after the transaction commits.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)
    old_key = Map.get(changeset.data, attribute)

    if Ash.Changeset.changing_attribute?(changeset, attribute) and is_binary(old_key) do
      Ash.Changeset.after_transaction(changeset, fn
        _changeset, {:ok, record} ->
          if Map.get(record, attribute) != old_key, do: Campfire.Uploads.delete(old_key)
          {:ok, record}

        _changeset, error ->
          error
      end)
    else
      changeset
    end
  end
end
