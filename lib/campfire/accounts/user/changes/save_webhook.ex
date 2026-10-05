defmodule Campfire.Accounts.User.Changes.SaveWebhook do
  @moduledoc """
  Saves the bot's webhook from the `:webhook_url` argument. An omitted argument leaves the webhook
  alone; nil or blank deletes it; otherwise the `Webhook` is upserted (one per user).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Accounts.Webhook

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn changeset, user ->
      case Changeset.fetch_argument(changeset, :webhook_url) do
        :error -> {:ok, user}
        {:ok, url} -> save(user, url |> to_string() |> String.trim())
      end
    end)
  end

  defp save(user, "") do
    user_id = user.id

    # System work inside the user action: the actor was already authorized for it.
    Webhook
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, return_errors?: true)

    {:ok, user}
  end

  defp save(user, url) do
    # System work inside the user action: the actor was already authorized for it.
    with {:ok, _webhook} <-
           Webhook
           |> Changeset.for_create(:create, %{user_id: user.id, url: url})
           |> Ash.create(authorize?: false) do
      {:ok, user}
    end
  end
end
