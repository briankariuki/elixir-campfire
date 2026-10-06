defmodule Campfire.Chat.Opengraph.Document do
  @moduledoc """
  Extracts the preview of an HTML page: `og:title`, `og:description`, `og:image`,
  `og:site_name` and `og:url`, falling back to `<title>` and `<meta name="description">`.

  The result is the map stored in `Message.embed` (string keys `"url"`, `"title"`,
  `"description"`, `"image_url"`, `"site_name"`), or `nil` when the page has no title. Texts are
  whitespace-collapsed and limited in length (the original Campfire shows 280 and 560
  characters); the image URL is made absolute and must be `http(s)`. `og:url` is only used when it
  is on the page's own host (so a page can't make its preview link elsewhere), else the fetched
  URL is.
  """

  @max_title 280
  @max_description 560
  @max_site_name 100
  @max_url 2_048

  @doc "Parses `html` fetched from `page_uri` (a `URI`)."
  @spec parse(String.t(), URI.t()) :: map() | nil
  def parse(html, %URI{} = page_uri) when is_binary(html) do
    document = html |> to_utf8() |> LazyHTML.from_document()
    meta = meta_tags(document)

    title =
      clean(meta["og:title"], @max_title) || clean(meta["twitter:title"], @max_title) ||
        clean(title_tag(document), @max_title)

    if title do
      %{
        "url" => canonical_url(meta["og:url"], page_uri),
        "title" => title,
        "description" =>
          clean(
            meta["og:description"] || meta["twitter:description"] || meta["description"],
            @max_description
          ),
        "image_url" => absolute_http_url(meta["og:image"] || meta["og:image:url"], page_uri),
        "site_name" => clean(meta["og:site_name"], @max_site_name)
      }
    end
  end

  # %{"og:title" => content, ...}: `property` and `name` both count, the first tag wins.
  defp meta_tags(document) do
    document
    |> LazyHTML.query("meta")
    |> LazyHTML.attributes()
    |> Enum.reduce(%{}, fn attributes, acc ->
      attributes = Map.new(attributes)

      case attributes do
        %{"content" => content} ->
          ["property", "name"]
          |> Enum.flat_map(&List.wrap(attributes[&1]))
          |> Enum.reduce(acc, &Map.put_new(&2, &1 |> String.trim() |> String.downcase(), content))

        _ ->
          acc
      end
    end)
  end

  defp title_tag(document) do
    document |> LazyHTML.query("title") |> Enum.at(0) |> then(&(&1 && LazyHTML.text(&1)))
  end

  defp canonical_url(url, page_uri) do
    with url when is_binary(url) <- absolute_http_url(url, page_uri),
         %URI{host: host} <- URI.parse(url),
         true <- same_site?(host, page_uri.host) do
      url
    else
      _ -> page_uri |> Map.put(:fragment, nil) |> URI.to_string()
    end
  end

  defp same_site?(host, other) when is_binary(host) and is_binary(other),
    do: strip_www(String.downcase(host)) == strip_www(String.downcase(other))

  defp same_site?(_host, _other), do: false

  defp strip_www("www." <> rest), do: rest
  defp strip_www(host), do: host

  defp absolute_http_url(nil, _page_uri), do: nil

  defp absolute_http_url(url, page_uri) do
    url = url |> String.trim() |> String.replace(~r/[\s\p{Cc}]/u, "")

    with true <- url != "" and byte_size(url) <= @max_url,
         {:ok, uri} <- URI.new(url),
         %URI{scheme: scheme, host: host, userinfo: nil} = absolute <- URI.merge(page_uri, uri),
         true <- scheme in ["http", "https"] and is_binary(host) and host != "",
         result = URI.to_string(absolute),
         true <- byte_size(result) <= @max_url do
      result
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp clean(nil, _max), do: nil

  defp clean(text, max) do
    text = text |> String.replace(~r/[\s\p{Cc}]+/u, " ") |> String.trim()

    cond do
      text == "" -> nil
      String.length(text) > max -> String.slice(text, 0, max - 1) <> "…"
      true -> text
    end
  end

  # Pages are read whole (a truncated body is refused), so invalid UTF-8 means another encoding;
  # ISO-8859-1 is the one old pages use.
  defp to_utf8(body) do
    if String.valid?(body), do: body, else: :unicode.characters_to_binary(body, :latin1, :utf8)
  end
end
