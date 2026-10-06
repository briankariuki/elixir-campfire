defmodule Campfire.Chat.Message.Changes.FetchEmbed do
  @moduledoc """
  The body of the `:fetch_embed` Oban job: fetches the link preview of the message's first link
  (synchronously, `transaction? false` on the action: no transaction is held during the HTTP
  call) and stores it with `:set_embed`, which broadcasts the message. Never fails the job: a
  link that can't be previewed leaves the message without an embed. See `Campfire.Chat.Opengraph`.

  The message is read again after the fetch: if it was edited meanwhile so that its first link is
  no longer the one fetched (or it was deleted), the result is dropped, since the edit enqueued
  its own job.
  """

  use Ash.Resource.Change

  require Logger

  alias Campfire.Chat.{Message, Opengraph}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      fetch_and_store(message)
      {:ok, message}
    end)
  end

  defp fetch_and_store(%Message{attachment_key: nil, body: body} = message) do
    with url when is_binary(url) <- Opengraph.first_url(body) do
      case Opengraph.preview(url) do
        {:ok, embed} ->
          store(message.id, url, embed)

        other ->
          Logger.info("No link preview for message #{message.id} (#{url}): #{inspect(other)}")
      end
    end
  end

  defp fetch_and_store(_message), do: :ok

  # System work: no actor, the author didn't ask for this update.
  defp store(id, url, embed) do
    with {:ok, %Message{} = current} <-
           Ash.get(Message, id, authorize?: false, not_found_error?: false),
         true <- Opengraph.first_url(current.body) == url and current.embed != embed do
      current
      |> Ash.Changeset.for_update(:set_embed, %{embed: embed}, authorize?: false)
      |> Ash.update()
      |> case do
        {:ok, _message} ->
          :ok

        {:error, error} ->
          Logger.warning("Storing the link preview of message #{id} failed: #{inspect(error)}")
      end
    else
      # Deleted, or edited to another first link (that edit enqueued its own job)
      _stale -> :ok
    end
  end
end
