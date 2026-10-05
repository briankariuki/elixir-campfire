defmodule Campfire.Accounts.User.Preparations.SignInRateLimitKey do
  @moduledoc """
  The `AshRateLimiter` bucket key for `User.sign_in`: the client IP (`:ip_address` argument) like
  the original Rails `rate_limit to: 10, within: 3.minutes`. Callers that pass no IP (scripts,
  tests) share a bucket per email address instead.
  """

  @spec key(Ash.Query.t(), map) :: String.t()
  def key(query, _context) do
    case Ash.Query.get_argument(query, :ip_address) do
      ip when is_binary(ip) and ip != "" ->
        "sign_in/ip/#{ip}"

      _ ->
        "sign_in/email/#{query |> Ash.Query.get_argument(:email_address) |> String.downcase()}"
    end
  end
end
