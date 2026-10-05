defmodule Campfire.Accounts.User.Validations.EmailAddress do
  @moduledoc """
  People must have an email address (it's how they sign in), and it must look like one: a
  single `@` with something on both sides and no whitespace. Deliberately lenient. Bots have
  no email address and don't use the actions that run this.

  Run it after `NormalizeEmail`, so surrounding whitespace has been trimmed.
  """

  use Ash.Resource.Validation

  @format ~r/\A[^@\s]+@[^@\s]+\z/

  @impl true
  def describe(_opts), do: [message: "must be a valid email address", vars: []]

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :email_address) do
      nil ->
        {:error, field: :email_address, message: "is required"}

      "" ->
        {:error, field: :email_address, message: "is required"}

      email ->
        if Regex.match?(@format, email),
          do: :ok,
          else: {:error, field: :email_address, message: "is invalid"}
    end
  end
end
