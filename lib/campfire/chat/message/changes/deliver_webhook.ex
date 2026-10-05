defmodule Campfire.Chat.Message.Changes.DeliverWebhook do
  @moduledoc """
  The body of the `:deliver_webhooks` Oban job: delivers the message to the bot in the
  `:bot_id` argument, synchronously. A transport failure fails the job (Oban retries it); a
  timeout posts the failure reply and completes it. See `Campfire.Webhooks`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, message ->
      bot_id = Ash.Changeset.get_argument(changeset, :bot_id)

      case Campfire.Webhooks.deliver_to_bot(message, bot_id) do
        :ok -> {:ok, message}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
