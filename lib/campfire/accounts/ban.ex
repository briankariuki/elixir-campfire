defmodule Campfire.Accounts.Ban do
  @moduledoc "A banned public IP address, recorded from a banned user's sessions."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Bitwise

  alias Campfire.Accounts.Ban.Actions.BannedIp

  postgres do
    table "bans"
    repo Campfire.Repo

    references do
      reference :user, on_delete: :delete
    end

    custom_indexes do
      index [:ip_address]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :ip_address]
    end

    action :banned_ip?, :boolean do
      description "Whether requests from that IP address are banned."
      argument :ip_address, :string
      run BannedIp
    end
  end

  policies do
    # Anyone may ask whether an IP is banned (checked before sign-in), but only get a yes/no.
    policy action(:banned_ip?) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :administrator)
    end
  end

  attributes do
    integer_primary_key :id

    attribute :ip_address, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end
  end

  @doc """
  Whether `ip` (a string or an `:inet` tuple) is a valid, public address. Loopback, private,
  link-local and unspecified addresses are not banned.
  """
  def public_ip?(ip) when is_binary(ip) do
    case :inet.parse_strict_address(String.to_charlist(String.trim(ip))) do
      {:ok, address} -> public_ip?(address)
      _ -> false
    end
  end

  def public_ip?({a, b, _c, _d}) do
    not (a == 0 or a == 10 or a == 127 or (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or (a == 192 and b == 168) or (a == 100 and b in 64..127))
  end

  def public_ip?({0, 0, 0, 0, 0, 0xFFFF, g, h}),
    do: public_ip?({g >>> 8, g &&& 255, h >>> 8, h &&& 255})

  def public_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  def public_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  def public_ip?({a, _, _, _, _, _, _, _}) when (a &&& 0xFE00) == 0xFC00, do: false
  def public_ip?({a, _, _, _, _, _, _, _}) when (a &&& 0xFFC0) == 0xFE80, do: false
  def public_ip?({_, _, _, _, _, _, _, _}), do: true
  def public_ip?(_), do: false
end
