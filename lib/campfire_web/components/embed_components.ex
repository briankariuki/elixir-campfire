defmodule CampfireWeb.EmbedComponents do
  @moduledoc """
  The link preview ("unfurl") card under a message, with the original Campfire's markup
  (`action_text/attachables/_opengraph_embed.html.erb`; the CSS is `embeds.css`, scoped to
  `.lexxy-content`).

  The embed is `Message.embed` (`url`, `title`, `description`, `image_url`, `site_name`, see
  `Campfire.Chat.Opengraph`). Links and the image are only rendered for `http(s)` URLs, whatever
  is stored. The image is loaded from the remote site by the browser, without a referrer.
  """
  use CampfireWeb, :html

  attr :embed, :map,
    default: nil,
    doc: "a message's `embed`; nothing is rendered for nil or empty"

  def embed(assigns) do
    assigns = assign(assigns, :card, card(assigns.embed))

    ~H"""
    <div :if={@card} class="lexxy-content">
      <figure class="attachment attachment--content attachment--og">
        <actiontext-opengraph-embed>
          <div class="og-embed gap">
            <div class="og-embed__content">
              <div class="og-embed__title">
                <a :if={@card.url} href={@card.url} target="_blank" rel="noopener noreferrer">{@card.title}</a>
                <span :if={!@card.url}>{@card.title}</span>
              </div>
              <div :if={@card.description} class="og-embed__description">{@card.description}</div>
              <div :if={@card.site_name} class="og-embed__site-name txt-subtle txt-small">
                {@card.site_name}
              </div>
            </div>
            <div :if={@card.image_url} class="og-embed__image">
              <img
                src={@card.image_url}
                class="image center"
                alt=""
                loading="lazy"
                referrerpolicy="no-referrer"
              />
            </div>
          </div>
        </actiontext-opengraph-embed>
      </figure>
    </div>
    """
  end

  # The values of the stored map (string keys from the database, atoms in memory), or nil when
  # there is nothing to show.
  defp card(embed) when is_map(embed) do
    case text(embed, :title) do
      nil ->
        nil

      title ->
        %{
          title: title,
          url: http_url(embed, :url),
          description: text(embed, :description),
          image_url: http_url(embed, :image_url),
          site_name: text(embed, :site_name)
        }
    end
  end

  defp card(_embed), do: nil

  defp value(embed, key), do: Map.get(embed, key) || Map.get(embed, Atom.to_string(key))

  defp text(embed, key) do
    case value(embed, key) do
      text when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  defp http_url(embed, key) do
    with url when is_binary(url) <- value(embed, key),
         %URI{scheme: scheme, host: host} when scheme in ["http", "https"] <- URI.parse(url),
         true <- is_binary(host) and host != "" do
      url
    else
      _ -> nil
    end
  end
end
