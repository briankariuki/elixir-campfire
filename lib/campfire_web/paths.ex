defmodule CampfireWeb.Paths do
  @moduledoc "URL helpers shared across the web layer."

  @doc """
  The avatar URL for a user, cache-busted by a hash of what the avatar shows (the uploaded
  file, or the initials of the name). Not `updated_at`: that changes on unrelated updates.
  """
  def avatar_path(%{id: id, avatar_key: avatar_key, name: name}) do
    "/users/#{id}/avatar?v=#{:erlang.phash2({avatar_key, name})}"
  end

  @doc "The permalink of a message: `/rooms/:room_id/@:message_id`."
  def message_path(%{id: id, room_id: room_id}), do: "/rooms/#{room_id}/@#{id}"

  @doc "The account logo URL."
  def logo_path(%{updated_at: updated_at}), do: "/account/logo?v=#{DateTime.to_unix(updated_at)}"
  def logo_path(_), do: "/account/logo"
end
