defmodule Campfire.Chat.Message.Notifiers.EnqueueEmbed do
  @moduledoc """
  After a message is created, or edited so that its first link changes, enqueues the
  `:fetch_embed` Oban job that fetches the link preview (`Campfire.Chat.Opengraph`). Notifiers run
  after the transaction commits, so the job always finds the message. Messages with an
  attachment, and messages without a previewable link (a mention, plain text), get no job.
  """

  use Ash.Notifier

  alias Ash.Notifier.Notification
  alias Campfire.Chat.{Message, Opengraph}

  @impl true
  def notify(%Notification{resource: Message, action: %{type: :create}, data: message}) do
    enqueue(message, nil)
  end

  def notify(%Notification{resource: Message, action: %{type: :update}} = notification) do
    enqueue(notification.data, notification.changeset.data.body)
  end

  def notify(_notification), do: :ok

  defp enqueue(%Message{attachment_key: nil} = message, old_body) do
    url = Opengraph.first_url(message.body)

    if url && url != Opengraph.first_url(old_body) do
      AshOban.run_trigger(message, :fetch_embed)
    end

    :ok
  end

  defp enqueue(_message, _old_body), do: :ok
end
