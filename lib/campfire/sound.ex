defmodule Campfire.Sound do
  @moduledoc """
  The 56 built-in `/play <name>` sounds.

  Each sound is either `{:text, caption}` or `{:image, file, width, height}`. The mp3 is served
  from `/sounds/<name>.mp3` and images from `/images/sounds/<file>`.
  """

  @sounds %{
    "56k" => {:image, "56k.webp", 79, 33},
    "bell" => {:text, "🔔"},
    "bezos" => {:text, "😆💭"},
    "bueller" => {:text, "anyone?"},
    "butts" => {:text, "👐 🚬"},
    "clowntown" => {:image, "clowntown.webp", 210, 150},
    "cottoneyejoe" => {:text, "🎶🙉🎶 "},
    "crickets" => {:text, "hears crickets chirping"},
    "curb" => {:image, "curb.webp", 150, 101},
    "dadgummit" => {:text, "dad gummit!! 🎣"},
    "dangerzone" => {:image, "dangerzone.webp", 157, 32},
    "danielsan" => {:text, "🎆 🏆 🎆"},
    "deeper" => {:image, "top.webp", 188, 80},
    "ballmer" => {:text, "developers!"},
    "donotwant" => {:image, "donotwant.webp", 150, 150},
    "drama" => {:image, "drama.webp", 300, 16},
    "flawless" => {:text, "#flawless"},
    "glados" => {:text, "🤖💢"},
    "gogogo" => {:text, "Go, go, go!"},
    "greatjob" => {:image, "greatjob.webp", 79, 16},
    "greyjoy" => {:text, "😖🎺"},
    "guarantee" => {:text, "guarantees it 👌"},
    "heygirl" => {:text, "✨💁✨"},
    "honk" => {:text, "HONK"},
    "horn" => {:text, "🐶 ✂️ 🐱"},
    "horror" => {:text, "💀 💀 💀 💀 💀 💀 💀"},
    "inconceivable" => {:text, "doesn't think it means what you think it means…"},
    "letitgo" => {:text, "❄️👩❄️⛄️❄️"},
    "live" => {:text, "is DOING IT LIVE"},
    "loggins" => {:image, "loggins.webp", 200, 151},
    "makeitso" => {:text, "make it so 👉"},
    "noooo" => {:text, "👸💀😒"},
    "nyan" => {:image, "nyan.webp", 36, 15},
    "ohmy" => {:text, "raises an eyebrow 😏"},
    "ohyeah" => {:text, "isn't playing by the rules"},
    "pushit" => {:image, "pushit.webp", 104, 15},
    "rimshot" => {:text, "plays a rimshot"},
    "rollout" => {:text, "is rolling out 🚗"},
    "rumble" => {:image, "rumble.webp", 220, 150},
    "sax" => {:text, "🌇🎷🎶"},
    "secret" => {:text, "found a secret area 🔑"},
    "sexyback" => {:text, "🔞"},
    "story" => {:text, "and now you know…"},
    "tada" => {:text, "plays a fanfare 🎏"},
    "tmyk" => {:text, "✨ ⭐️ The More You Know ✨ ⭐️"},
    "totes" => {:text, "😁👍"},
    "trololo" => {:text, "трололо"},
    "trombone" => {:text, "plays a sad trombone"},
    "unix" => {:text, "knows this 💻"},
    "vuvuzela" => {:text, "======<() ~ ♪ ~♫"},
    "what" => {:image, "what.webp", 100, 131},
    "whoomp" => {:text, "👏‼️😎"},
    "wups" => {:text, "wups!"},
    "yay" => {:image, "yay.webp", 103, 50},
    "yeah" => {:image, "yeah.webp", 104, 15},
    "yodel" => {:text, "📣🗻🙉"}
  }

  @names @sounds |> Map.keys() |> Enum.sort()

  @type t :: {:text, String.t()} | {:image, String.t(), pos_integer(), pos_integer()}

  @doc "All sound names, sorted."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "The sound with that name, or nil."
  @spec find(String.t()) :: t() | nil
  def find(name), do: Map.get(@sounds, name)

  @doc "Whether a sound with that name exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(name), do: Map.has_key?(@sounds, name)

  @doc "The URL path of the sound's mp3."
  def audio_path(name), do: "/sounds/#{name}.mp3"

  @doc "The URL path of an image file from `{:image, file, w, h}`."
  def image_path(file), do: "/images/sounds/#{file}"

  @doc """
  The sound name a message body plays, or nil. A body plays a sound when it is exactly
  `/play <name>` and `<name>` is a known sound.
  """
  @spec sound_name(String.t() | nil) :: String.t() | nil
  def sound_name("/play " <> _ = body) do
    case Regex.run(~r/\A\/play (\w+)\z/, body) do
      [_, name] -> if exists?(name), do: name
      _ -> nil
    end
  end

  # Not a `/play` command: no regex (every viewer of a room asks for every new message)
  def sound_name(_), do: nil
end
