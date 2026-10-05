# Development data: an account, people, rooms and a few messages. Run by `mix setup` and
# `mix ecto.setup`, or directly:
#
#     mix run priv/repo/seeds.exs
#
# Everyone's password is "secret123" (see the README). Skipped when the account already exists,
# and refused in production, where the first administrator comes from the /first_run page.

alias Campfire.{Accounts, Chat}

if Mix.env() == :prod do
  raise "priv/repo/seeds.exs creates accounts with a known password; don't run it in production"
end

if Accounts.set_up?() do
  IO.puts("Campfire is already set up; skipping seeds.")
else
  password = "secret123"

  %{user: alice, room: all_talk} =
    Accounts.first_run!(%{
      name: "Alice Admin",
      email_address: "alice@example.com",
      password: password
    })

  register = fn name, email ->
    Accounts.register_user!(%{name: name, email_address: email, password: password})
  end

  bob = register.("Bob Builder", "bob@example.com")
  carol = register.("Carol Coder", "carol@example.com")
  dave = register.("Dave Designer", "dave@example.com")

  bot = Accounts.create_bot!(%{name: "Deploy Bot"}, actor: alice)

  engineering =
    Chat.create_closed_room!("Engineering", [alice.id, bob.id, carol.id, bot.id], actor: alice)

  _design = Chat.create_open_room!("Design", actor: alice)
  direct = Chat.find_or_create_direct_room!([bob.id], actor: alice)

  say = fn room, user, body -> Chat.create_message!(room, %{body: body}, actor: user) end

  say.(all_talk, alice, "Welcome to Campfire! 👋")
  hello = say.(all_talk, bob, "Hi everyone, glad to be here.")
  say.(all_talk, carol, "Hey @Bob Builder, welcome aboard!")
  say.(all_talk, dave, "The new mockups are in the Design room.")
  Chat.create_boost!(hello, "🎉", actor: alice)

  say.(engineering, carol, "Deploying the release this afternoon.")
  say.(engineering, bot, "Deploy finished: v1.2.0 is live.")
  say.(engineering, bob, "Nice work @Carol Coder.")

  say.(direct, alice, "Can you review the room settings change?")
  say.(direct, bob, "On it.")

  IO.puts("""
  Seeded Campfire. Sign in at http://localhost:4000 with password "#{password}":

    alice@example.com  (administrator)
    bob@example.com
    carol@example.com
    dave@example.com

  Deploy Bot's key: #{Accounts.User.bot_key(bot)}
  """)
end
