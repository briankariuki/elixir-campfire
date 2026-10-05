defmodule Campfire.Random do
  @moduledoc "Cryptographically random tokens."

  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

  @doc "`length` random characters from `[A-Za-z0-9]`."
  def alphanumeric(length) do
    # Rejection sampling keeps the distribution uniform (248 = 4 * 62).
    Stream.repeatedly(fn -> :crypto.strong_rand_bytes(length * 2) end)
    |> Stream.flat_map(&:binary.bin_to_list/1)
    |> Stream.filter(&(&1 < 248))
    |> Enum.take(length)
    |> Enum.map(&Enum.at(@alphabet, rem(&1, 62)))
    |> List.to_string()
  end

  @doc "A url-safe base64 string of `bytes` random bytes."
  def url_token(bytes \\ 32) do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
