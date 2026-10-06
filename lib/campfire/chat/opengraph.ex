defmodule Campfire.Chat.Opengraph do
  @moduledoc """
  Link previews ("unfurling", the original Campfire's `Opengraph::*`): the OpenGraph data of the
  first link of a message, stored in `Message.embed`.

    * `first_url/1` picks the link a message previews;
    * `preview/1` fetches the page (`Campfire.Chat.Opengraph.Fetch`, with the SSRF protections
      described there) and parses it (`Campfire.Chat.Opengraph.Document`).

  The domain side is `Campfire.Chat.Message`: a notifier enqueues the `:fetch_embed` Oban job after
  a message with a link is created or its first link changes, and the job stores the preview with
  `:set_embed`, which broadcasts `{:message_updated, message}`.
  """

  require Logger

  alias Campfire.Chat.Opengraph.{Document, Fetch}

  # Same as the message body renderer's autolinking.
  @url_regex ~r{https?://[^\s<>"']*[^\s<>"'.,;:!?)\]]}u
  @quote_regex ~r/\A>(?: |\z)/
  @max_url_length 2_048
  # Files and media aren't pages (the original skips them too).
  @file_extensions ~w(zip tar gz tgz bz2 xz rar 7z dmg exe msi pkg deb iso jpg jpeg png gif bmp svg
                      webp heic heif mp4 mov avi mkv wmv flv mp3 wav ogg aac wma webm ogv mpg mpeg pdf)

  @doc """
  The first previewable link in `body`: an `http(s)` URL (no credentials, at most 2048 bytes, not
  a file or media link), ignoring quoted lines (`> ...`, as in replies). `nil` if there is none.
  """
  @spec first_url(String.t() | nil) :: String.t() | nil
  def first_url(body) when is_binary(body) do
    body
    |> String.split(["\r\n", "\n"])
    |> Enum.reject(&Regex.match?(@quote_regex, &1))
    |> Enum.flat_map(&(@url_regex |> Regex.scan(&1) |> List.flatten()))
    |> Enum.find(&previewable?/1)
  end

  def first_url(_body), do: nil

  @doc """
  Fetches the preview of `url`: `{:ok, embed}` (the map for `Message.embed`), `:none` when the page
  has nothing to show, or `{:error, reason}`. Never raises.
  """
  @spec preview(String.t()) :: {:ok, map()} | :none | {:error, term()}
  def preview(url) when is_binary(url) do
    with {:ok, %{uri: uri, body: body}} <- Fetch.get(url) do
      case Document.parse(body, uri) do
        nil -> :none
        embed -> {:ok, embed}
      end
    end
  rescue
    exception ->
      Logger.debug("Link preview of #{url} failed: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp previewable?(url) do
    byte_size(url) <= @max_url_length and match?({:ok, _}, Fetch.parse(url)) and
      not file?(url)
  end

  defp file?(url) do
    extension = url |> URI.parse() |> Map.get(:path) |> to_string() |> Path.extname()
    String.downcase(String.trim_leading(extension, ".")) in @file_extensions
  end
end
