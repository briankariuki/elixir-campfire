defmodule Campfire.Accounts.Errors.AlreadySetUp do
  @moduledoc "Returned by the `Account` `:first_run` action when an account already exists."

  use Splode.Error, fields: [], class: :invalid

  @impl true
  def message(_error), do: "Campfire is already set up"
end
