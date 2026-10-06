defmodule CampfireWeb.BrowserSupport do
  @moduledoc """
  Which browsers Campfire supports, decided from the `User-Agent` header (the original's
  `AllowBrowser` concern, which delegates to Rails' `allow_browser` and the `useragent` gem).

  The minimum versions are the original's:

      safari 17.2, chrome 120, firefox 121, opera 104, ie unsupported (any version)

  `blocked?/1` follows `allow_browser`'s semantics:

    * no `User-Agent`, or one without a recognisable version, is let through
    * browsers that aren't listed (Edge, Samsung Internet, Chromium, curl, app webviews, ...) are
      let through; only the browsers in `versions/0` are guarded
    * crawlers and link-preview fetchers are let through: Googlebot, for one, reports an old
      `Chrome/` version, and the original takes care to show Apple Messages (which spoofs
      `facebookexternalhit` + `Twitterbot`) no "Unsupported browser" page. This is a superset of
      Rails' own bot exemption
    * a version is supported when it is `>=` the minimum, comparing dotted numbers segment by
      segment (`17.2.1 >= 17.2`, `17.10 > 17.2`)

  Browsers are told apart by their UA tokens, most specific first: IE (`MSIE`/`Trident`), Edge
  (`Edg`), other Chromium skins, Opera (`OPR`), Firefox (`Firefox`/`FxiOS`), Chrome
  (`Chrome`/`CriOS`), Safari (`Version/x ... Safari/`).
  """

  # Insertion order is the display order of the "unsupported browser" page. `false` blocks every
  # version of that browser.
  @versions [safari: "17.2", chrome: "120", firefox: "121", opera: "104", ie: false]

  # Matched as substrings (no regexes: they can't live in module attributes on recent OTP).
  @bots ~w(Googlebot AdsBot-Google Feedfetcher-Google Mediapartners-Google APIs-Google
           Google-InspectionTool Storebot-Google GoogleOther bingbot Slurp wget Wget curl
           Twitterbot WhatsApp facebookexternalhit)

  # Browsers built on Chromium/WebKit that carry a `Chrome/` token but have their own version
  # numbering. Like Edge they aren't guarded.
  @other_chromium ~w(Edg/ Edge/ EdgA/ EdgiOS/ SamsungBrowser/ UCBrowser/ YaBrowser/ Vivaldi/
                     Chromium/ DuckDuckGo/ Silk/)

  @doc "The guarded browsers and their minimum versions (`false`: unsupported at any version)."
  def versions, do: @versions

  @doc "Whether a request with this `User-Agent` should get the \"unsupported browser\" page."
  @spec blocked?(String.t() | nil) :: boolean()
  def blocked?(user_agent) do
    case classify(user_agent) do
      {browser, version} -> below_minimum?(Keyword.get(@versions, browser), version)
      _unguarded -> false
    end
  end

  @doc """
  Classifies a `User-Agent`: `{browser, version}` for the guarded browsers (version is a list of
  integers), `:bot`, `:other` or `:unknown`.
  """
  @spec classify(String.t() | nil) ::
          {:safari | :chrome | :firefox | :opera | :ie, [non_neg_integer()]}
          | :bot
          | :other
          | :unknown
  def classify(user_agent) when is_binary(user_agent) and user_agent != "" do
    cond do
      String.contains?(user_agent, @bots) ->
        :bot

      version = token_version(user_agent, "MSIE ") ->
        {:ie, version}

      String.contains?(user_agent, "Trident/") ->
        {:ie, token_version(user_agent, "rv:") || []}

      String.contains?(user_agent, @other_chromium) ->
        :other

      version = token_version(user_agent, "OPR/") ->
        {:opera, version}

      String.starts_with?(user_agent, "Opera/") ->
        {:opera, token_version(user_agent, "Version/") || []}

      version = token_version(user_agent, "Firefox/") ->
        {:firefox, version}

      version = token_version(user_agent, "FxiOS/") ->
        {:firefox, version}

      version = token_version(user_agent, "Chrome/") ->
        {:chrome, version}

      version = token_version(user_agent, "CriOS/") ->
        {:chrome, version}

      version = safari_version(user_agent) ->
        {:safari, version}

      true ->
        :other
    end
  end

  def classify(_user_agent), do: :unknown

  defp safari_version(user_agent) do
    if String.contains?(user_agent, "Safari/"), do: token_version(user_agent, "Version/")
  end

  # The dotted number right after `token`, as integers (`"Chrome/120.0.6099.1"` -> `[120, 0, 6099, 1]`).
  defp token_version(user_agent, token) do
    with {pos, len} <- :binary.match(user_agent, token),
         rest = binary_part(user_agent, pos + len, byte_size(user_agent) - pos - len),
         <<first, _::binary>> when first in ?0..?9 <- rest do
      rest |> take_version(<<>>) |> parse_version()
    else
      _ -> nil
    end
  end

  defp take_version(<<char, rest::binary>>, acc) when char in ?0..?9 or char == ?.,
    do: take_version(rest, <<acc::binary, char>>)

  defp take_version(_rest, acc), do: acc

  defp parse_version(string) do
    string |> String.split(".", trim: true) |> Enum.map(&String.to_integer/1)
  end

  # `false`: the whole browser is unsupported (IE), whether or not it reports a version.
  defp below_minimum?(false, _version), do: true
  # A browser that doesn't report a version is let through, like `allow_browser`.
  defp below_minimum?(_minimum, []), do: false

  defp below_minimum?(minimum, version),
    do: compare_versions(version, parse_version(minimum)) == :lt

  defp compare_versions([], []), do: :eq
  defp compare_versions(a, []), do: compare_versions(a, [0])
  defp compare_versions([], b), do: compare_versions([0], b)

  defp compare_versions([a | rest_a], [b | rest_b]) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> compare_versions(rest_a, rest_b)
    end
  end
end
