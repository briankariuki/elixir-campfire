defmodule Campfire.OpengraphResolver do
  @moduledoc """
  The link preview host resolver in tests (`config :campfire, :opengraph_resolver`): no real DNS,
  fixed addresses. Hosts: `example.com` and `other.example.com` are public, `internal.example.com`,
  `localhost` and `mapped.example.com` resolve to private addresses, `mixed.example.com` to a public
  and a private one; any other name doesn't exist.
  """

  @hosts %{
    "example.com" => [{93, 184, 216, 34}],
    "www.example.com" => [{93, 184, 216, 34}],
    "other.example.com" => [{93, 184, 216, 35}],
    "internal.example.com" => [{10, 0, 0, 5}],
    "localhost" => [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}],
    "mapped.example.com" => [{0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}],
    "mixed.example.com" => [{93, 184, 216, 34}, {192, 168, 1, 1}]
  }

  def resolve(host) do
    case Map.fetch(@hosts, host) do
      {:ok, ips} -> {:ok, ips}
      :error -> {:error, :nxdomain}
    end
  end
end
