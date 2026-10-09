defmodule Campfire.Chat.Opengraph.Address do
  @moduledoc """
  Which IP addresses link previews may connect to: global unicast addresses only.

  Refused (IPv4 and IPv6): unspecified, loopback, private (RFC 1918, unique local), link-local
  (incl. the cloud metadata address 169.254.169.254), carrier-grade NAT, multicast, broadcast,
  documentation, benchmarking and every other reserved range. IPv4-mapped (`::ffff:a.b.c.d`),
  NAT64 (`64:ff9b::/96`) and 6to4 (`2002::/16`) IPv6 addresses are judged by the IPv4 address they
  embed, so they can't smuggle a private address past the check.
  """

  import Bitwise

  @type ip :: :inet.ip_address()

  @doc "Whether `ip` is a public address a preview may connect to."
  @spec public?(ip()) :: boolean()
  def public?({a, b, c, d} = ip) when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255,
    do: not reserved_v4?(ip)

  # IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::a.b.c.d): the embedded IPv4 decides.
  def public?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: public?(v4(hi, lo))
  def public?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}), do: public?(v4(hi, lo))
  # 6to4 embeds the IPv4 address in the next 32 bits.
  def public?({0x2002, hi, lo, _, _, _, _, _}), do: public?(v4(hi, lo))
  # Teredo (2001::/32) tunnels to arbitrary hosts, 2001::/23 is the IETF protocol range.
  def public?({0x2001, second, _, _, _, _, _, _}) when second < 0x200, do: false
  # Documentation (2001:db8::/32 and 3fff::/20).
  def public?({0x2001, 0xDB8, _, _, _, _, _, _}), do: false
  def public?({0x3FFF, second, _, _, _, _, _, _}) when second < 0x1000, do: false

  # Of IPv6 only global unicast (2000::/3) is public; this excludes ::, ::1, ULA (fc00::/7),
  # link-local (fe80::/10), multicast (ff00::/8) and everything unassigned.
  def public?({first, _, _, _, _, _, _, _}) when first in 0x2000..0x3FFF, do: true

  def public?(_ip), do: false

  defp v4(hi, lo), do: {hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF}

  defp reserved_v4?({a, b, c, _d}) do
    a == 0 or
      a == 10 or
      a == 127 or
      a >= 224 or
      (a == 100 and b in 64..127) or
      (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or
      (a == 192 and b == 0 and c in [0, 2]) or
      (a == 192 and b == 88 and c == 99) or
      (a == 192 and b == 168) or
      (a == 198 and b in 18..19) or
      (a == 198 and b == 51 and c == 100) or
      (a == 203 and b == 0 and c == 113)
  end
end
