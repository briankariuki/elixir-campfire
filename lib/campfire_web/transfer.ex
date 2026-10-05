defmodule CampfireWeb.Transfer do
  @moduledoc """
  Session transfer links ("sign in on another device"): a signed token for the user id that is
  valid for 4 hours and reusable until it expires.
  """
  use CampfireWeb, :verified_routes

  @salt "transfer"
  @max_age 4 * 60 * 60

  @doc "The transfer URL for `user`: `/session/transfers/<token>`."
  def url(user), do: Phoenix.VerifiedRoutes.unverified_url(CampfireWeb.Endpoint, path(user))

  @doc "The transfer path for `user`."
  def path(user), do: ~p"/session/transfers/#{token(user)}"

  @doc "A signed transfer token for `user`."
  def token(%{id: id}), do: Phoenix.Token.sign(CampfireWeb.Endpoint, @salt, id)

  @doc "Verifies a token: `{:ok, user_id}` or `{:error, :invalid | :expired | :missing}`."
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(CampfireWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_token), do: {:error, :missing}
end
