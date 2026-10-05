# Domain API cheat-sheet

What the web layer calls. Everything lives in `lib/campfire/**` (no `CampfireWeb` dependency).
Read `docs/PORTING.md` for the product rules; this file only describes the functions.

## Conventions

- Code interface functions come in pairs: `fun(...)` returns `{:ok, result}` / `{:error, error}`,
  and `fun!(...)` returns the result or raises.
- The last argument is a keyword list of options. Pass **`actor: current_user`** on every call
  from the web, unless the table below says "no actor". Other useful options: `load: [...]`
  (load relationships/calculations on the result), `authorize?: false` (internal use only).
- Create and update functions take a `params` map after the positional args, for example
  `Chat.update_closed_room(room, %{name: "x", user_ids: [1, 2]}, actor: user)`.
- Destroy functions return `:ok` (or `{:error, error}`).
- Errors:
  - A failing write policy gives `{:error, %Ash.Error.Forbidden{}}`.
  - Reads are **filtered** by policy. A record you can't see gives `{:error, %Ash.Error.Invalid{}}` (NotFound)
    from `get_*`, and lists simply leave it out.
  - Validation errors give `{:error, %Ash.Error.Invalid{}}`. AshPhoenix forms work with every action, e.g.
    `AshPhoenix.Form.for_create(Campfire.Chat.Room, :create_open, actor: user)`.
- Policy pre-checks: for each interface Ash also generates `can_<name>?(actor, ...same args...)`, which returns a
  boolean. Use it to show or hide buttons. For example, `Chat.can_update_message?(user, message)` decides the edit
  button, and `Chat.can_create_open_room?(user, "x")` decides the "+" button.
- Timestamps are `inserted_at` / `updated_at` (`DateTime`, usec). Ids are integers.

## `Campfire.Accounts`

### Account (single row)

| Function | Actor | Returns / notes |
|---|---|---|
| `get_account()` | no actor | `{:ok, %Account{} \| nil}` (`get_account!()` returns the account or nil) |
| `set_up?()` | no actor | `true` once first run has happened (predicate interface: bare boolean; `set_up()` gives `{:ok, boolean}`) |
| `valid_join_code?(code)` | no actor | boolean (constant-time compare; `nil` is false) |
| `first_run(%{name, email_address, password, avatar_key?})` | no actor | `{:ok, %{account:, user:, room:}}`: one transaction that creates the account, an **administrator**, and the open room "All Talk" (with the admin as a member). If an account exists: `{:error, %Ash.Error.Invalid{errors: [%Campfire.Accounts.Errors.AlreadySetUp{}]}}`. `first_run!/1` raises instead |
| `update_account(account, %{name?, logo_key?, restrict_room_creation_to_administrators?})` | admin | `{:ok, account}`. A replaced `logo_key` file is deleted |
| `reset_join_code(account)` | admin | `{:ok, account}` with a new `join_code` (`XXXX-XXXX-XXXX`) |

`%Account{}` fields: `id, name, join_code, logo_key, restrict_room_creation_to_administrators`.

### Users

| Function | Actor | Returns / notes |
|---|---|---|
| `register_user(%{name, email_address, password, bio?, avatar_key?})` | no actor | `{:ok, user}` (role `:member`). Joins every open room. The email is trimmed and lowercased; a duplicate email gives `{:error, %Ash.Error.Invalid{}}`. **The caller checks the join code** with `valid_join_code?/1` |
| `sign_in(email, password, %{ip_address: ip})` | no actor | `{:ok, %User{}}` or `{:ok, nil}`. Active non-bot users only (bcrypt; timing-safe when the user doesn't exist). The optional `ip_address` input keys the rate limit (10 calls per 3 minutes, failed or not; keyed on the email when omitted). Over the limit: `{:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{}]}}` (the controller renders 429) |
| `authenticate_bot(bot_key)` | no actor | `{:ok, %User{}}` or `{:ok, nil}`. The key is `"<id>-<token>"`. Active bots only; `Plug.Crypto.secure_compare`; an empty token is rejected |
| `get_user(id)` | any user | `{:ok, user}` |
| `get_user_for_avatar(id)` | no actor | `{:ok, %User{} \| nil}` with only `id, name, role, avatar_key, updated_at` selected. For the public avatar route (an invalid id gives `{:error, _}`) |
| `get_active_user(id)` | no actor | `{:ok, %User{} \| nil}`, `nil` unless `status == :active`. For session-transfer links (the caller still rejects bots) |
| `first_administrator()` | no actor | `{:ok, %User{} \| nil}`: the oldest administrator, shown as the help contact on the sign-in pages |
| `list_users_by_ids(ids)` | any user | `[%User{}]` for those ids (`list_users_by_ids!/2`). Without an actor it returns `[]`; message rendering, which has no actor, passes `authorize?: false` |
| `list_users(%{include_banned: false, include_bots: false})` | any user | Active people ordered by name. The params map is optional. Admins' account page: `%{include_banned: true}` |
| `list_bots()` | admin | Active bots ordered by name, with `:webhook` loaded (`bot.webhook && bot.webhook.url`) |
| `update_profile(user, %{name?, email_address?, bio?, avatar_key?, password?})` | the user themself | `{:ok, user}`. A blank or missing password keeps the old one. A replaced avatar file is deleted |
| `set_last_room(user, room_id)` | the user themself | `{:ok, user}` (`last_room_id`) |
| `change_role(user, role)` | admin | `role` is `:administrator` (or `"administrator"`); anything else means `:member`. Bots can't be changed (Invalid) |
| `deactivate_user(user)` | admin, not self | `{:ok, user}`. Deletes non-direct memberships, sessions and searches; status `:deactivated`; email becomes `name-deactivated-<uuid>@host`; disconnects sockets. Also used to "delete" a bot |
| `ban_user(user)` | admin, not self | `{:ok, user}`. Bans each public session IP (private and loopback IPs are skipped), deletes sessions, status `:banned`, disconnects sockets, then enqueues the Oban job that deletes all their messages (each broadcasts `{:message_deleted, m}`) |
| `unban_user(user)` | admin | `{:ok, user}`. Deletes the bans; status `:active` (messages aren't restored) |
| `create_bot(%{name, avatar_key?, webhook_url?})` | admin | `{:ok, bot}` (role `:bot`, 12-char `bot_token`). Joins the open rooms. Creates the webhook when a URL is given (it must be `http(s)://`) |
| `update_bot(bot, %{name?, avatar_key?, webhook_url?})` | admin | `{:ok, bot}`. An omitted `webhook_url` leaves the webhook unchanged; a nil or blank one **deletes** it; otherwise it is created or updated |
| `reset_bot_key(bot)` | admin | `{:ok, bot}` with a new `bot_token` |

`%User{}` fields: `id, name, email_address, bio, role (:member | :administrator | :bot),
status (:active | :deactivated | :banned), bot_token, avatar_key, last_room_id, inserted_at, updated_at`
(`password_hash` is never needed).
Loadable: `:initials`, `:bot_key`, `:webhook`, `:memberships`, `:rooms`.

Helpers on `Campfire.Accounts.User`: `initials(user)` ("JF"), `bot_key(user)` (`"<id>-<token>"`, nil for people),
`administrator?/1`, `bot?/1`, `active?/1`, and `can_administer?(user, record)` (admin, or `record.creator_id == user.id`).

### Sessions and bans

| Function | Actor | Returns / notes |
|---|---|---|
| `create_session(%{ip_address, user_agent})` | **the user signing in** (`actor: user`) | `{:ok, %Session{token: ...}}`. Put `session.token` in the Plug session as `:session_token` |
| `get_session_by_token!(token)` | no actor | `%Session{user: %User{}}` or `nil` (`get_session_by_token/1` wraps it in `{:ok, _}`). Only returns sessions whose user is **active**. Authorization is off by default (the token is the credential) |
| `touch_session(session, %{ip_address, user_agent})` | the session's user | `{:ok, session}`. The action itself writes only if `last_active_at` is more than 1h old; a fresh session is returned unchanged |
| `destroy_session(session)` | the session's user | `:ok`. Logout; disconnects that user's sockets |
| `banned_ip?(ip_string)` | no actor | boolean, for the `block_banned_ip` plug (predicate interface; `banned_ip(ip)` gives `{:ok, boolean}`) |

Login flow: `{:ok, %User{} = user} = Accounts.sign_in(email, pw, %{ip_address: UserAuth.ip_string(conn)})` →
`{:ok, session} = Accounts.create_session(%{ip_address: ip, user_agent: ua}, actor: user)` →
`put_session(conn, :session_token, session.token)` + `put_session(conn, :live_socket_id, "users_socket:#{user.id}")`.
Request flow: `Accounts.get_session_by_token!(token)` → `session.user`, then `Accounts.touch_session(session, ..., actor: session.user)`.

## `Campfire.Chat`

### Rooms

| Function | Actor | Returns / notes |
|---|---|---|
| `list_rooms()` | any user | The actor's rooms (all kinds), ordered by name. Includes rooms the actor made invisible |
| `get_room(id)` | member | `{:ok, room}`, or NotFound for non-members |
| `create_open_room(name)` | active person; admin only when the account restricts room creation | `{:ok, room}`. Every active user (bots included) becomes a member with involvement `:mentions` |
| `create_closed_room(name, user_ids)` | same as above | `{:ok, room}`. Only `user_ids` become members. **The creator isn't added automatically** (the form pre-checks them) |
| `find_or_create_direct_room(user_ids)` | any active user | `{:ok, room}`. The actor is always included. Returns the existing DM for exactly that set of users, or creates one (involvement `:everything`). Idempotent |
| `update_open_room(room, %{name?})` | admin or creator | Renames. A closed room becomes open and every active user is granted. Direct rooms give Invalid |
| `update_closed_room(room, %{name?, user_ids})` | admin or creator | Renames. An open room becomes closed. Grants new ids and revokes the rest (they get `{:room_removed, id}`). Direct rooms give Invalid |
| `destroy_room(room)` | open/closed: admin or creator; direct: any member | `:ok`. Deletes memberships, messages, boosts and attachment files |

`%Room{}` fields: `id, name (nil for direct), kind (:open | :closed | :direct), creator_id, direct_key, inserted_at,
updated_at` (`updated_at` is bumped by every new or edited message, so you can sort DMs by it).
Loadable: `:users` (members), `:memberships`, `:creator`, `:messages`.
For example, `Chat.get_room!(id, actor: user, load: [:users])`.
`Room.default_involvement(room)` returns `:everything` for direct rooms and `:mentions` otherwise.

### Memberships

| Function | Actor | Returns / notes |
|---|---|---|
| `list_memberships()` | any user | The actor's memberships with `:room` loaded (all involvements; the sidebar hides `:invisible`). For DM names: `load: [room: [:users]]` |
| `get_membership(room_id)` | any user | `{:ok, membership \| nil}`: the actor's own membership in that room |
| `set_involvement(membership, involvement)` | own membership | `:invisible \| :nothing \| :mentions \| :everything`. Broadcasts `:sidebar_changed` to the user |
| `mark_read(membership)` | own membership | Sets `unread_at = nil`; broadcasts `{:room_read, room_id}` to the user. Call it when RoomLive tracks presence |
| `revoke_membership(membership)` | admin or room creator | `:ok`. Broadcasts `{:room_removed, room_id}` and `:sidebar_changed` to that user |

`%Membership{}` fields: `id, room_id, user_id, involvement, unread_at (nil = read)`.

### Messages

| Function | Actor | Returns / notes |
|---|---|---|
| `create_message(room, %{body?, client_message_id?, attachment_key?, attachment_filename?, attachment_content_type?, attachment_byte_size?, deliver_webhooks?: true})` | member of `room` (people and bots) | `{:ok, message}` with `:creator` and `boosts: [:booster]` loaded. `room` is a `%Room{}`. Needs a non-blank body or an `attachment_key`. `client_message_id` defaults to a UUID. Side effects: mentions resolved, room touched, unread marks, broadcasts, bot webhooks |
| `update_message(message, %{body})` | creator or admin (a bot only its own messages) | `{:ok, message}` (loaded like create). Mentions are re-resolved; broadcasts `{:message_updated, m}` |
| `destroy_message(message)` | creator or admin (a bot only its own messages) | `:ok`. Deletes the attachment file; broadcasts `{:message_deleted, m}` |
| `get_message(id)` | member of its room | `{:ok, message}`. Add `load: [:creator, :room, boosts: [:booster]]` as needed |
| `page_messages(room_id, %{before: id} \| %{after: id} \| %{around: id} \| %{})` | any user (non-members get `[]`) | `{:ok, [message]}`: 40 per page (`Message.page_size()`), **ascending** by `(inserted_at, id)`, with `:creator` and `boosts: [:booster]` loaded. No cursor gives the last 40. `around` returns up to 40 before + the message + up to 40 after, or the last page if the message is gone. A `before`/`after` cursor that is gone (deleted, or not in the room) pages by id instead (`id < cursor` / `id > cursor`). More pages exist when the result is non-empty for `%{before: hd(page).id}` |
| `search_messages(query)` | any user | `{:ok, [message]}`: the last 100 matches in the actor's rooms, ascending, with `:creator` and `:room` loaded. Uses `plainto_tsquery('english', ...)` over the body plus the attachment filename; only word characters are kept from the query, and a blank query gives `[]` |
| `count_messages(room_id, actor: user)` | member | `{:ok, n}` (for the bot API's `X-Total-Count`) |

`%Message{}` fields: `id, room_id, creator_id, body (plain text, "" when attachment-only), client_message_id,
mentioned_user_ids ([integer]), attachment_key, attachment_filename, attachment_content_type, attachment_byte_size,
inserted_at, updated_at`.

Helpers on `Campfire.Chat.Message` (plain functions, no loading needed):
`plain_text(m)` (the body, else the filename, else `""`), `content_type(m)` (`:attachment | :sound | :text`),
`sound_name(m)` (a `/play` sound name or nil), `attachment?(m)`. The same values are loadable as the calculations
`:plain_text` and `:content_type`.

Mentions: the body holds `@Full Name` text. When a message is saved, every `@Name` that matches a **room member**
exactly (longest names first, not followed by a letter, digit or `_`) ends up in `mentioned_user_ids`.
To highlight mentions when rendering, use `Campfire.Chat.Mentions.mention_regex(name)` for each mentioned user's name.
`Mentions.room_members(room_id)` returns `[{id, name}]`.

Attachments (web composer or bot API): `{:ok, key} = Campfire.Uploads.store(tmp_path, client_name)`, then
`create_message(room, %{attachment_key: key, attachment_filename: name, attachment_content_type: type,
attachment_byte_size: size}, actor: user)`. One file per message.

### Boosts

| Function | Actor | Returns / notes |
|---|---|---|
| `create_boost(message, content)` | member of the message's room | `{:ok, boost}` with `:booster` loaded. `content` is 1..16 characters (Invalid otherwise). Broadcasts `{:boost_created, boost}` |
| `destroy_boost(boost)` | **the booster only** (no admin override) | `:ok`. Broadcasts `{:boost_deleted, boost}` |
| `get_boost(id)` | member of the message's room | `{:ok, boost}` |

`%Boost{}` fields: `id, message_id, room_id (denormalized from the message), booster_id, content, inserted_at`. Messages load boosts ordered oldest first.

### Recent searches

| Function | Actor | Returns / notes |
|---|---|---|
| `record_search(query)` | any user | `{:ok, search}`. Upserts on `(user, query)` and touches it; keeps only the 10 newest |
| `recent_searches()` | any user | The actor's searches, newest first |
| `clear_searches()` | any user | `:ok`. Deletes all of the actor's searches |

## Realtime (`Campfire.Broadcast`, Phoenix.PubSub `Campfire.PubSub`)

Subscribe with `Campfire.Broadcast.subscribe_room(room_id)`, `subscribe_user(user_id)` and `subscribe_typing(room_id)`.
Topic helpers: `room_topic/1`, `user_topic/1`, `typing_topic/1`, `presence_topic/1`, `socket_id/1`.

| Topic | Message | When |
|---|---|---|
| `"room:<id>"` | `{:message_created, %Message{creator, boosts}}` | message created (web, bot API, webhook reply) |
| `"room:<id>"` | `{:message_updated, %Message{creator, boosts}}` | message edited |
| `"room:<id>"` | `{:message_deleted, %Message{}}` | message destroyed (also during ban cleanup) |
| `"room:<id>"` | `{:boost_created, %Boost{booster}}` / `{:boost_deleted, %Boost{}}` | boost added or removed (use `boost.message_id`) |
| `"room:<id>:typing"` | `{:typing, :start \| :stop, %{id:, name:}}` | **the web layer** sends this itself (`Phoenix.PubSub.broadcast_from`) |
| `"user:<id>"` | `{:room_unread, room_id}` | a new message, sent to **every** member (author included; ignore it for the open room) |
| `"user:<id>"` | `{:room_read, room_id}` | `mark_read` |
| `"user:<id>"` | `:sidebar_changed` | room created, updated or destroyed; membership granted or revoked; involvement changed |
| `"user:<id>"` | `{:room_removed, room_id}` | room destroyed, or the user was removed from it |
| `"users_socket:<id>"` | `%Phoenix.Socket.Broadcast{event: "disconnect"}` | logout (`destroy_session`), deactivate, ban |

All broadcasts are sent **after the transaction commits**.

## Presence (`Campfire.Presence`)

A `Phoenix.Presence` started by the application. RoomLive, while the tab is visible:
`Campfire.Presence.track_user(self(), room_id, user.id)` (key `to_string(user_id)` on `"presence:room:<room_id>"`)
and `Campfire.Presence.untrack_user(self(), room_id, user.id)` when hidden. Then call `Chat.mark_read/2`.
`Campfire.Presence.present_user_ids(room_id)` returns the list of ids. Present members are not marked unread.

## Uploads (`Campfire.Uploads`)

Files are stored on local disk under `config :campfire, :uploads_dir` (default `priv/uploads`, a tmp dir in test,
the `UPLOADS_DIR` env var at runtime).

- `store(source_path, filename) :: {:ok, key}`: copies the file. `filename` only provides the extension.
- `store_binary(binary, filename) :: {:ok, key}`
- `path(key)`: the absolute path to `send_file`
- `exists?(key)` and `delete(key)` (nil and missing keys are fine)

Keys go into `users.avatar_key`, `accounts.logo_key` and `messages.attachment_key`.

## Sounds (`Campfire.Sound`)

- `names()`: 56 names, sorted
- `find(name)`: `{:text, caption}`, `{:image, file, width, height}` or `nil`
- `exists?(name)`
- `sound_name(body)`: the name when `body` is exactly `/play <known name>`
- `audio_path(name)`: `"/sounds/<name>.mp3"`
- `image_path(file)`: `"/images/sounds/<file>"`

## Bots and webhooks (`Campfire.Webhooks`)

Delivery is automatic after `create_message` (unless `deliver_webhooks?: false`). The eligible bots are every active
bot member in a direct room, otherwise the active bots in `mentioned_user_ids`; the creator is always excluded.
`Campfire.Notifiers.Fanout` calls `Campfire.Webhooks.enqueue_for_message/2` after the message commits, which inserts one
Oban job per eligible bot with a webhook (AshOban trigger `:deliver_webhooks` on `Message`, queue `:webhooks`, 3 attempts,
run through the update action `Message.deliver_webhooks` with a `bot_id` argument). The job `POST`s the PORTING.md §5 JSON
(7s timeouts) and posts the reply as that bot with `deliver_webhooks?: false`:

- a `text/plain` or `text/html` 2xx response with a non-blank body becomes a text message (HTML is stripped to text);
- any other 2xx response with a body becomes an attachment `attachment.<ext>`;
- a timeout posts `"Failed to respond within 7 seconds"` and completes the job, so retries never re-post it;
- a connection-level failure (refused, DNS, closed) fails the job and Oban retries it (3 attempts in total); other
  non-2xx responses are logged and not retried.

Bot API flow: `{:ok, %User{} = bot} = Accounts.authenticate_bot(params["bot_key"])` (401 on `nil`).
Then `Chat.get_room(room_id, actor: bot)` (404 on error), then `Chat.create_message(room, %{body: raw_body}, actor: bot)`,
`Chat.page_messages(room.id, %{before: id}, actor: bot)`, `Chat.update_message/3` and `Chat.destroy_message/2`
(403 on Forbidden), and `Chat.create_boost(message, raw_body, actor: bot)`. Check `message.room_id == room.id` and
return 404 when they differ.

Ban cleanup is the same pattern: `User.ban` enqueues (after commit) the `:remove_banned_content` trigger, whose update
action deletes the user's messages. It only runs for users that are still `:banned` and is safe to run again.

Config (`config/*.exs`): `config :campfire, Oban` (queues `default` and `webhooks`; the pruner and lifeline plugins).
Both triggers have `scheduler_cron false`: nothing polls, jobs are only enqueued explicitly. In test `Oban` runs with
`testing: :inline`, so jobs run in the enqueueing process and the webhook/ban tests need no draining. To look at the queue
or run retries, wrap the test body in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)` with `use AshOban.Test,
repo: Campfire.Repo` and use `assert_triggered/3` and `Oban.drain_queue(queue: :webhooks, with_scheduled: true)`
(see `test/campfire/webhooks_test.exs`). `:webhook_req_options` (test: `plug: {Req.Test, Campfire.Webhooks}`, so stub with
`Req.Test.stub(Campfire.Webhooks, fn conn -> ... end)`).

## Testing helpers

`test/support/fixtures.ex` (`import Campfire.Fixtures`) provides `account_fixture/1`, `user_fixture/1`
(`role: :administrator` supported), `admin_fixture/1`, `bot_fixture/1`, `open_room_fixture/2`,
`closed_room_fixture/3`, `direct_room_fixture/2`, `message_fixture/3`, `session_fixture/2` and `reload/1`.
