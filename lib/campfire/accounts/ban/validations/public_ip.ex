defmodule Campfire.Accounts.Ban.Validations.PublicIp do
  @moduledoc """
  The `ip_address` must parse as an IPv4/IPv6 address and be public: loopback, private,
  link-local and unspecified addresses can't be banned (they would lock out everyone behind
  the same proxy, or the server itself).
  """

  use Ash.Resource.Validation

  alias Campfire.Accounts.Ban

  @impl true
  def describe(_opts), do: [message: "must be a public IP address", vars: []]

  @impl true
  def validate(changeset, _opts, _context) do
    ip = Ash.Changeset.get_attribute(changeset, :ip_address)

    cond do
      not is_binary(ip) or not valid_ip?(ip) ->
        {:error, field: :ip_address, message: "is not a valid IP address"}

      not Ban.public_ip?(ip) ->
        {:error, field: :ip_address, message: "cannot be a private or internal IP address"}

      true ->
        :ok
    end
  end

  defp valid_ip?(ip) do
    match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(String.trim(ip))))
  end
end
