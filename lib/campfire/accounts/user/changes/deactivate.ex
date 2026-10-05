defmodule Campfire.Accounts.User.Changes.Deactivate do
  @moduledoc """
  Deactivates a user: frees their email address for reuse (mangled with a UUID) and, in the same
  transaction, removes their non-direct memberships and recent searches. Sessions and sockets
  are handled by `DestroySessions` and `DisconnectSockets`.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.Membership

  # Reads the current email, so actions using this change need `require_atomic? false`.
  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.change_attribute(:status, :deactivated)
    |> mangle_email(changeset.data.email_address)
    |> Changeset.after_action(fn _changeset, user ->
      Membership.revoke_all_except_direct(user.id)

      # Cross-domain system work; `:clear` deletes the *actor's* searches, so act as the
      # deactivated user (the administrator who triggered this is not the owner).
      Campfire.Chat.clear_searches!(actor: user, authorize?: false)
      {:ok, user}
    end)
  end

  defp mangle_email(changeset, email) when is_binary(email) do
    if email =~ "@" do
      mangled = String.replace(email, "@", "-deactivated-#{Ecto.UUID.generate()}@")
      Changeset.change_attribute(changeset, :email_address, mangled)
    else
      changeset
    end
  end

  defp mangle_email(changeset, _email), do: changeset
end
