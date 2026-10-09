defmodule CampfireWeb.SocketSerializerTest do
  use ExUnit.Case, async: true

  alias CampfireWeb.SocketSerializer
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.V2.JSONSerializer

  defp diff(html, topic \\ "lv:phx-test") do
    %Message{
      join_ref: "4",
      ref: nil,
      topic: topic,
      event: "diff",
      payload: %{
        0 => %{
          2 => %{
            7 => %{
              stream: [
                "0",
                [["messages-#{System.unique_integer([:positive])}", -1, -300, false]],
                []
              ],
              k: %{0 => %{0 => html, s: 0}, kc: 1}
            }
          }
        },
        p: %{0 => ["", ""]}
      }
    }
  end

  defp frame!({:socket_push, :text, iodata}),
    do: iodata |> IO.iodata_to_binary() |> Phoenix.json_library().decode!()

  test "a diff with templates is the same frame as the stock serializer's" do
    message = diff(~s(<div id="m1" class="message">café "quoted" \u{1F44D}</div>))

    assert frame!(SocketSerializer.encode!(message)) == frame!(JSONSerializer.encode!(message))
  end

  test "the second encode of the same payload is served from the cache, only the envelope differs" do
    first = diff("<div>same</div>", "lv:phx-first")
    second = %{first | topic: "lv:phx-second", join_ref: "9"}

    SocketSerializer.encode!(first)
    size = CampfireWeb.MessageBody.Cache.size(CampfireWeb.FrameCache)
    {:socket_push, :text, iodata} = SocketSerializer.encode!(second)

    assert CampfireWeb.MessageBody.Cache.size(CampfireWeb.FrameCache) == size
    assert frame!({:socket_push, :text, iodata}) == frame!(JSONSerializer.encode!(second))
    assert [_, nil, "lv:phx-second", "diff", %{"p" => _}] = frame!({:socket_push, :text, iodata})
  end

  test "different payloads are different frames" do
    a = frame!(SocketSerializer.encode!(diff("<div>a</div>")))
    b = frame!(SocketSerializer.encode!(diff("<div>b</div>")))

    refute a == b
  end

  test "diffs without templates, replies and other pushes are the stock serializer's" do
    plain = %Message{
      join_ref: "1",
      ref: nil,
      topic: "lv:x",
      event: "diff",
      payload: %{0 => %{1 => "small"}}
    }

    other = %Message{
      join_ref: "1",
      ref: nil,
      topic: "lv:x",
      event: "live_patch",
      payload: %{kind: :push, to: "/rooms/1"}
    }

    reply = %Phoenix.Socket.Reply{
      join_ref: "1",
      ref: "2",
      topic: "lv:x",
      status: :ok,
      payload: %{diff: %{}}
    }

    for message <- [plain, other, reply] do
      assert SocketSerializer.encode!(message) == JSONSerializer.encode!(message)
    end
  end

  test "decode! and fastlane! are the stock ones" do
    raw = ~s(["1","2","lv:x","event",{"a":1}])

    assert SocketSerializer.decode!(raw, opcode: :text) ==
             JSONSerializer.decode!(raw, opcode: :text)

    broadcast = %Phoenix.Socket.Broadcast{topic: "t", event: "e", payload: %{a: 1}}
    assert SocketSerializer.fastlane!(broadcast) == JSONSerializer.fastlane!(broadcast)
  end
end
