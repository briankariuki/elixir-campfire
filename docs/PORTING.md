# Porting Campfire (Rails) to Elixir — Phoenix + LiveView + Ash

This is the plan and the contract for rewriting [basecamp/once-campfire](https://github.com/basecamp/once-campfire)
in Elixir. Guiding rule: **keep it simple**. Port the product, not the Rails plumbing.

Detailed analysis of the original (read when you need exact behavior):

- [`docs/analysis/01-domain.md`](analysis/01-domain.md): tables, business rules, bots/webhooks, search, bans
- [`docs/analysis/02-web.md`](analysis/02-web.md): every route, auth, bot API, realtime broadcasts
- [`docs/analysis/03-ui.md`](analysis/03-ui.md): every screen, markup and CSS class names, JS behaviors

The Rails source is MIT licensed; CSS, icons and sounds are copied over as-is.

---

## 1. What Campfire is

A self-hosted, single-tenant group chat:

- **One account** (name, logo, join code). The first visitor runs "first run" setup and becomes admin.
  Others join with an invite link `/join/<join_code>`.
- **Users** have a role (`member`, `administrator`, `bot`) and a status (`active`, `deactivated`, `banned`).
- **Rooms** come in three kinds:
  - **open**: everyone is a member automatically.
  - **closed**: an explicit member list.
  - **direct**: a DM ("Ping") between an exact set of users, without a name.
- **Memberships** link users to rooms. Each has an **involvement** level (`invisible | nothing | mentions | everything`)
  and an `unread_at` timestamp.
- **Messages** have a text body, an optional single file attachment, `@mentions`, and `/play <sound>` commands.
- **Boosts** are short reactions (≤16 chars, usually an emoji) on a message.
- **Bots** are users with a `bot_key`. They post through a small HTTP API. An optional **webhook** is called when
  the bot is @mentioned, or for every message in a DM with the bot; the webhook's response is posted as the bot's reply.
- **Search** covers the messages in your rooms and keeps your 10 recent searches.
- **Admin tools**: change roles, deactivate users, ban (IP bans plus deleting the user's messages), manage bots,
  regenerate the join code, rename the account and set its logo, and restrict room creation to admins.
- **Realtime** features: new, edited and deleted messages, boosts, unread dots in the sidebar, typing indicators,
  and presence (people viewing a room don't get unread marks).

## 2. Rails → Elixir mapping

| Rails | Elixir port |
|---|---|
| ActiveRecord models + concerns | **Ash resources** in two domains, `Campfire.Accounts` and `Campfire.Chat` |
| SQLite + FTS5 | **Postgres** via AshPostgres. Search uses a generated `tsvector` column with a GIN index |
| STI `Rooms::Open/Closed/Direct` | One `rooms` table with a `kind` atom attribute (`:open | :closed | :direct`) |
| ActionText rich text (Lexxy editor) | Plain-text `body` column; rendered with HTML escaping, autolinks, line breaks, `> quote` blocks and mentions |
| ActionText mention attachments (sgid) | `@Full Name` in the text, resolved against room members when saved and stored in `mentioned_user_ids` (int array) |
| ActiveStorage | Files on local disk under a configurable uploads dir (`Campfire.Uploads`); keys stored in columns |
| ActionCable channels + Turbo Streams | **Phoenix.PubSub** topics plus LiveView `handle_info` |
| `memberships.connected_at/connections` presence | **Phoenix.Presence** (`Campfire.Presence`, topic `"presence:room:<id>"`) |
| Resque jobs (webhook, ban cleanup) | Oban jobs through AshOban triggers (`Message :deliver_webhooks`, `User :remove_banned_content`) |
| `has_secure_password` | `bcrypt_elixir` (`Bcrypt.hash_pwd_salt/1`, `Bcrypt.verify_pass/2`) |
| `has_secure_token` sessions + signed cookie | `sessions` table with a random token, stored in the Plug session (`:session_token`) |
| Signed ids (transfer links) | `Phoenix.Token.sign(CampfireWeb.Endpoint, "transfer", user_id)`, `max_age: 4h` |
| Stimulus controllers | LiveView built-ins, plus a handful of small `phx-hook`s |
| Propshaft CSS | The original CSS files, bundled by esbuild. **No Tailwind/daisyUI** |
| Net::HTTP webhooks | `Req` with 7s timeouts |

### Dropped for simplicity

Web Push and VAPID, PWA (manifest and service worker), QR codes, OpenGraph link unfurling, custom CSS, translation popups,
the browser-version gate, version headers, image thumbnails and video previews (originals are served and sized with CSS),
the rich-text toolbar, Sentry, `Purchaser`, the `/rooms/:id/refresh` catch-up endpoint and the heartbeat channel
(a LiveView remount covers both).

**Involvement levels stay** (`invisible` hides a room from the sidebar). Without push, the other levels have no effect,
but the bell UI still cycles through them so the data model matches the original.

---

## 3. Domain model (Ash)

All tables use integer `id` primary keys and `inserted_at`/`updated_at` (`utc_datetime_usec`).

### Domain `Campfire.Accounts`

**`Campfire.Accounts.Account`**: a single row (`singleton_guard` integer, default 0, with a unique identity).
- `name` (string, required, default `"Campfire"`), `join_code` (string, required), `logo_key` (string, nullable),
  `restrict_room_creation_to_administrators` (boolean, default false).
- `join_code` format: 12 random alphanumerics split into 4-character groups joined by `-`, e.g. `CRMu-l8Ge-KB9B`.
- Actions: `get` (read the one account), `create` (first run), `update` (name, logo_key, restrict flag),
  `reset_join_code`.

**`Campfire.Accounts.User`**
- `name` (required), `email_address` (unique identity, nullable for bots), `password_hash` (sensitive), `bio`,
  `role` (atom: `:member | :administrator | :bot`, default `:member`),
  `status` (atom: `:active | :deactivated | :banned`, default `:active`),
  `bot_token` (string, unique, nullable), `avatar_key` (nullable), `last_room_id` (nullable; set by `set_last_room`, used by `/`).
- Calculations and helpers: `initials` (the first letter of each word), `bot_key` = `"#{id}-#{bot_token}"`.
- Actions:
  - `register`: name, email, password, optional avatar_key. Hashes the password and grants membership to every open room.
    The first-run variant creates an administrator.
  - `sign_in`: a read action taking email and password. Active users only; verifies with bcrypt.
  - `update_profile`: name, email, bio, optional password, avatar_key.
  - `change_role` (admin): only `member` or `administrator`.
  - `deactivate` (admin): delete non-direct memberships, sessions and searches; set status `:deactivated`;
    rewrite the email to `String.replace(email, "@", "-deactivated-#{uuid}@")`; disconnect sockets.
  - `ban` (admin):
    - Create a `Ban` for each distinct public IP among the user's sessions (skip private IPs; don't fail on them).
    - Delete the sessions, set status `:banned` and disconnect sockets.
    - Delete all of the user's messages in a background task, broadcasting each deletion.
  - `unban` (admin): delete the bans, set status `:active`.
  - `create_bot` (admin): name, optional avatar_key, optional webhook_url. role `:bot`, random 12-char `bot_token`;
    joins open rooms.
  - `update_bot` (admin): a blank webhook_url deletes the webhook.
  - `reset_bot_key` (admin).
  - `authenticate_bot(bot_key)`: split on `-`, look up an **active bot** by id, and compare the token in constant time
    (`Plug.Crypto.secure_compare`). Reject an empty token.
- The `can_administer?(user, record)` rule: `user.role == :administrator or record.creator_id == user.id`.

**`Campfire.Accounts.Session`**: `user_id`, `token` (random 32-byte url-safe string, unique), `ip_address`, `user_agent`,
`last_active_at`. Actions: `create`, `get_by_token`, `touch` (only if `last_active_at` is more than 1h old), `destroy`.

**`Campfire.Accounts.Ban`**: `user_id`, `ip_address` (indexed). `banned_ip?(ip)`.

**`Campfire.Accounts.Webhook`**: `user_id` (unique), `url`. Delivery is described in §5.

### Domain `Campfire.Chat`

**`Campfire.Chat.Room`**
- `name` (nullable for direct), `kind` (`:open | :closed | :direct`), `creator_id`,
  `direct_key` (string, nullable, unique: the sorted member ids joined with `-`, for DMs only).
- Actions:
  - `create_open(name)`: create the room and grant memberships to all **active** users (bots included).
  - `create_closed(name, user_ids)`: grant only `user_ids`. The creator is **not** added automatically; the form pre-checks them.
  - `find_or_create_direct(user_ids)`: the ids always include the actor. Look up by `direct_key`, else create with
    every membership's involvement set to `:everything`.
  - `update_open(name)`: rename. A closed room becomes open and every active user is granted membership.
  - `update_closed(name, user_ids)`: rename. An open room becomes closed. Grant new ids and revoke the missing ones.
  - `destroy`: deletes memberships, messages and boosts.
  - Direct rooms can never change `kind`.
- Read actions: `for_user` (rooms the actor is a member of), `get_for_user(id)`.
- Default involvement: `:mentions` for open and closed rooms, `:everything` for direct rooms.
- Every grant is idempotent (unique `(room_id, user_id)`; upsert or `on_conflict: :nothing`).

**`Campfire.Chat.Membership`**: `room_id`, `user_id` (unique pair), `involvement` (atom, default `:mentions`), `unread_at`.
- Actions:
  - `set_involvement`: own membership only.
  - `mark_read`: `unread_at = nil`, then broadcast `{:room_read, room_id}` to `"user:<id>"`.
  - `revoke`: broadcast `{:room_removed, room_id}` to `"user:<id>"`.

**`Campfire.Chat.Message`**
- `room_id`, `creator_id`, `body` (text, may be empty), `client_message_id` (string, required; generate a UUID when blank),
  `mentioned_user_ids` ({:array, :integer}, default `[]`),
  `attachment_key`, `attachment_filename`, `attachment_content_type`, `attachment_byte_size` (all nullable),
  `search_vector` (a generated column, `to_tsvector('english', coalesce(body,'') || ' ' || coalesce(attachment_filename,''))`,
  added through a custom migration statement).
- Calculations and helpers: `plain_text` (the body, else the attachment filename, else `""`), `content_type`
  (`:attachment | :sound | :text`). `:sound` applies when the body matches `~r/\A\/play (\w+)\z/` and the name is in `Campfire.Sound`.
- Actions:
  - `create` (actor = creator, must be a member):
    - Resolve mentions: every `@Full Name` in the body that matches a room member, longest name first.
    - Touch `room.updated_at`.
    - Then, as after-action side effects:
      1. Set `unread_at = message.inserted_at` on memberships where involvement ≠ `:invisible`, user ≠ creator,
         and the user is **not present** in `Campfire.Presence.list("presence:room:<id>")`.
      2. Broadcast `{:message_created, message}` to `"room:<id>"`, and `{:room_unread, room_id}` to `"user:<uid>"`
         for every member.
      3. Unless the `deliver_webhooks?` argument is false (it is false for webhook replies), deliver webhooks (§5)
         to eligible bots: in a direct room, every active bot member; otherwise, the active bots in `mentioned_user_ids`.
         The creator is always excluded.
  - `update(body)`: admin or creator (bots: creator only). Re-resolves mentions, broadcasts `{:message_updated, message}`.
  - `destroy`: admin or creator. Deletes the file and broadcasts `{:message_deleted, message}`.
- Read actions:
  - `page(room_id, before: id | after: id | around: id)`: 40 per page, ordered `(inserted_at, id)` ascending.
    The default is the last 40.
  - `search(query)`: messages in the actor's rooms matching `plainto_tsquery('english', q)`. Returns the last 100,
    ascending.

**`Campfire.Chat.Boost`**: `message_id`, `booster_id`, `content` (string, 1..16 chars, required).
- Actions:
  - `create`: must be a member of the message's room. Broadcasts `{:boost_created, boost}` to `"room:<id>"`.
  - `destroy`: the booster only. Broadcasts `{:boost_deleted, boost}`.

**`Campfire.Chat.Search`**: `user_id`, `query`.
- Actions:
  - `record(query)`: upsert on `(user_id, query)` and touch `updated_at`, then keep only the 10 newest.
  - `recent`: the actor's searches, newest first.
  - `clear`: delete all of the actor's searches.

**`Campfire.Sound`**: a plain module holding the static list of 56 sounds (name → `{:text, "..."}` or `{:image, file, w, h}`).
The full table is in `analysis/03-ui.md` §3.3.

### Authorization

Use **Ash policies** with `actor` on every resource that users touch from the web. Server-internal calls
(the webhook-reply job, first run, seeds and tests of internals) pass `authorize?: false`. Key rules:

| Action | Rule |
|---|---|
| Room read | the actor has a membership (filter policy) |
| Create an open or closed room | any active non-bot user, unless the account restricts creation to admins → admin only |
| Create a direct room | any user |
| Update or destroy an open or closed room | admin or creator |
| Destroy a direct room | any member |
| Message create / read | member of the room |
| Message update / destroy | admin or creator (bots: creator only) |
| Boost create | member of the message's room; boost destroy: the booster only |
| Membership involvement / mark_read | own membership |
| Account update, join code reset, role change, deactivate, ban, unban, bot management | admin |

---

## 4. Realtime contract (PubSub)

`Campfire.PubSub` already exists. **The domain layer emits these; the web layer only subscribes.**
`Campfire.Broadcast` holds the topic names and subscribe helpers.

Broadcasts come from `Ash.Notifier.PubSub` (`Message`, `Boost`, `Membership`) and from the custom notifier
`Campfire.Notifiers.Fanout` (per-member fan-outs and bot webhooks, attached per action), both sent after the outermost
transaction commits. `Campfire.PubSubBroadcaster` is the PubSub notifier's `broadcast/3` module: it turns the
`%Ash.Notifier.Notification{}` into the tuples below and sends them over `Campfire.PubSub`, so subscribers never see
Ash structs. Bulk actions that must notify pass `notify?: true`.

| Topic | Message | Emitted by |
|---|---|---|
| `"room:<room_id>"` | `{:message_created, %Message{}}` | Message.create (web, bot API, webhook reply) |
| `"room:<room_id>"` | `{:message_updated, %Message{}}` | Message.update |
| `"room:<room_id>"` | `{:message_deleted, %Message{}}` | Message.destroy, ban cleanup |
| `"room:<room_id>"` | `{:boost_created, %Boost{}}` / `{:boost_deleted, %Boost{}}` | Boost actions |
| `"room:<room_id>:typing"` | `{:typing, :start \| :stop, %{id: user_id, name: name}}` | the web layer (`broadcast_from`) |
| `"user:<user_id>"` | `{:room_unread, room_id}` | Message.create, sent to every member |
| `"user:<user_id>"` | `{:room_read, room_id}` | Membership.mark_read |
| `"user:<user_id>"` | `:sidebar_changed` | any room create/update/destroy, membership grant/revoke, or involvement change for that user (the sidebar simply reloads) |
| `"user:<user_id>"` | `{:room_removed, room_id}` | room destroyed, or membership revoked (RoomLive navigates away) |

Presence: `Campfire.Presence` (a `Phoenix.Presence` started in the application). `RoomLive` tracks
`self()` under key `to_string(user_id)` on `"presence:room:<id>"` while the tab is visible, and calls `mark_read` on
track.

Socket disconnect: when a user is logged out, deactivated or banned, call
`CampfireWeb.Endpoint.broadcast("users_socket:#{user_id}", "disconnect", %{})`. The login code sets `live_socket_id` to that value.

---

## 5. Bots and webhooks (a public contract: keep the shapes)

**Bot API** (pipeline `:bot_api`: no session, no CSRF; the `:bot_key` path param is authenticated; 401 when invalid):

| Method | Path | Behavior |
|---|---|---|
| GET | `/rooms/:room_id/:bot_key/messages[?before=id\|after=id]` | 200 JSON array (40, ascending). `X-Total-Count` header, plus `Link: <…?before=first_id>; rel="next"` when older messages exist (or `after=last_id` when paging forward) |
| POST | `/rooms/:room_id/:bot_key/messages` | Raw request body = message text, **or** a multipart `attachment` file. 422 if both are blank. 201 with the message JSON |
| PUT/PATCH | `/rooms/:room_id/:bot_key/messages/:id` | Raw body = new text. 200 with JSON; 403 if not the creator |
| DELETE | `/rooms/:room_id/:bot_key/messages/:id` | 204; 403 if not the creator |
| POST | `/rooms/:room_id/:bot_key/messages/:message_id/boosts` | Raw body = content. 201 with the boost JSON; 422 if blank |
| DELETE | `/rooms/:room_id/:bot_key/messages/:message_id/boosts/:id` | 204; 404 if not the bot's own boost |

A room the bot isn't a member of, or a message outside that room, returns **404**.

Raw body: `Plug.Parsers` consumes form bodies, so the Endpoint uses a `body_reader` (`CampfireWeb.CacheBodyReader`)
that stores the raw body in `conn.assigns[:raw_body]`.

JSON shapes:

```jsonc
// message
{"id": 1, "created_at": "2024-01-01T00:00:00Z",
 "body": {"plain_text": "Hello", "html": "<p>Hello</p>"},
 "creator": {"id": 2, "name": "Bot", "role": "bot", "avatar_url": "https://host/users/2/avatar"},
 "room": {"id": 3}, "url": "https://host/rooms/3/@1"}
// boost
{"id": 9, "content": "👀", "created_at": "…",
 "booster": {"id": 2, "name": "Bot", "role": "bot", "avatar_url": "…"},
 "message": {"id": 1, "url": "https://host/rooms/3/@1"}}
```

**Webhook delivery** runs as an Oban job per bot (AshOban): `POST url`, JSON, 7s connect/receive timeout.

```json
{"user":    {"id": 1, "name": "David"},
 "room":    {"id": 3, "name": "Watercooler", "path": "/rooms/3/<bot_key>/messages"},
 "message": {"id": 7, "body": {"html": "<p>…</p>", "plain": "text with '@BotName' removed, trimmed"},
             "path": "/rooms/3/@7"}}
```

Reply handling:
- A 2xx response with content type `text/plain` or `text/html` and a non-blank body becomes a text message from the bot.
- Any other 2xx response with a body is saved as an attachment `attachment.<ext>`.
- A timeout posts the text `"Failed to respond within 7 seconds"`.
- Replies are created with `deliver_webhooks?: false`, so bots can't loop.

---

## 6. Web layer (Phoenix + LiveView)

### Plugs and auth (`CampfireWeb.UserAuth`)
- `fetch_current_user`: Plug session `:session_token` → Session → active user, assigned as `:current_user`;
  calls `touch` on the session.
- `require_authenticated_user`: redirects to `/session/new` and stores `:return_to`. `redirect_if_user_is_authenticated`
  sends signed-in users away from the join and login pages. On `/session/new`, redirect to `/first_run` when no account exists.
- `block_banned_ip`: a non-GET/HEAD request from a banned IP gets 429.
- `on_mount {CampfireWeb.UserAuth, :ensure_authenticated}` and `{..., :ensure_admin}`.
- Login puts `:session_token` and `:live_socket_id` (`"users_socket:<id>"`) in the session.

### Routes

```
GET  /up                                   health
GET  /first_run, POST /first_run           FirstRunController   (only while no Account exists)
GET  /session/new, POST /session           SessionController
DELETE /session                            SessionController
GET  /session/transfers/:token, PUT …      SessionTransferController (GET renders a confirm button; PUT logs in)
GET  /join/:join_code, POST …              JoinController       (guest only; 404 on a bad code)
GET  /account/logo                         public; default campfire-icon.png
GET  /users/:id/avatar                     avatar file or a generated initials SVG (18 colors; see analysis/03-ui §1.19)
GET  /attachments/:message_id              authenticated + member; ?download=1 → attachment disposition

live_session :authenticated
  /                         HomeLive          redirect to the last room (users.last_room_id or the oldest room) or an empty state
  /rooms/:id                RoomLive :show
  /rooms/:id/@:message_id   RoomLive :at_message
  /rooms/new/open           RoomFormLive :new_open
  /rooms/new/closed         RoomFormLive :new_closed
  /rooms/:id/edit           RoomFormLive :edit (direct: participants + delete)
  /directs/new              DirectPickerLive
  /searches                 SearchLive (?q=)
  /users/:id                UserLive (Ping button; admin: ban/unban, transfer link)
  /profile                  ProfileLive (name/email/password/bio/avatar, memberships with bells, transfer link, logout)
  /account                  AccountLive (logo, name, restrict switch, invite link + regenerate, users: crown toggle, remove)
live_session :admin
  /account/bots             BotsLive :index
  /account/bots/new         BotsLive :new
  /account/bots/:id/edit    BotsLive :edit (+ regenerate key, delete)

scope "/rooms/:room_id/:bot_key", pipe_through :bot_api   (see §5)
```

### LiveViews
- **Sidebar**: a function component rendered by each authenticated LiveView from assigns loaded by an `on_mount` hook
  (`CampfireWeb.Sidebar`). The hook subscribes to `"user:<id>"` and handles `:sidebar_changed`, `{:room_unread, id}`
  and `{:room_read, id}` with `attach_hook(:handle_info)`. This beats a sticky nested LiveView for simplicity.
  - Direct rooms come first, newest first. Then shared rooms by name. Up to 20 "Ping" placeholders for users you have no DM with.
  - A "+" new-room button (hidden when room creation is restricted), plus profile and settings links at the bottom.
- **RoomLive**: the message stream (`stream(:messages, …)`, DOM id `"messages-#{client_message_id}"`) and
  the `MessagePager` hook (not `phx-viewport-top`, see `room_live.ex`) to load older and newer pages on scroll.
  - Composer: a `<textarea>` with Enter to send, plus `allow_upload(:attachments, max_entries: 10)`; each file becomes
    its own message.
  - Message options: 8 quick boosts (👍 👏 👋 💪 ❤️ 😂 🎉 🔥), a custom boost, reply (prefills `> quote`), copy link,
    and edit/delete inline.
  - Also: the typing indicator, presence tracking, the involvement bell, and `/play` sounds (played only for messages that
    arrive live).
- **SearchLive**: recent searches in the sidebar slot; results use the same message component with the room label shown.

### Message rendering (`CampfireWeb.MessageComponents`)
Use the original markup and classes (`analysis/03-ui.md` §3):
- `.message`, `.message--me`, `.message--mentioned`, `.message--emoji` and `.message--formatted` are computed on the server.
- `.message--threaded` (same author within 5 minutes) and `.message--first-of-day` (day separator) are set by a small
  JS hook, because they depend on the neighbouring messages and the viewer's time zone.

Body rendering, in order:
1. HTML-escape.
2. Autolink `https?://…` (`target="_blank" rel="noopener"`).
3. Turn `> ` lines into `<blockquote>`.
4. Replace each mentioned `@Name` with `<span class="mention">…</span>`.
5. Turn newlines into `<br>`.
6. Wrap in `<div class="lexxy-content">`.

### JS hooks (`assets/js/hooks/*.js`, kept small)
- `MessageList`: scrolls to the bottom on mount and on new messages when the user was near the bottom; keeps the
  scroll position when older messages are prepended; sets the threaded and first-of-day classes; plays `/play` sounds
  when the server sends a `play_sound` push_event.
- `Composer`: Enter sends (Shift+Enter inserts a newline), the textarea auto-grows, pasted files are uploaded, and it
  throttles `typing` events.
- `LocalTime`: formats `<time datetime>` with `Intl.DateTimeFormat`.
- `Visibility`: pushes `visible`/`hidden` on `visibilitychange`, debounced 5s, to track or untrack presence.
- `Copy` (clipboard) and `Lightbox` (`<dialog>.showModal()`).

### CSS and assets
- Copy `app/assets/stylesheets/*.css` to `assets/css/campfire/`; `assets/css/app.css` `@import`s them in a fixed order.
  Fix the three `url()` references to point at `/images/...`.
- **Remove Tailwind and daisyUI**: delete the deps and config, bundle CSS with esbuild, and rewrite `core_components.ex`
  down to what we use (flash, input helpers) using Campfire's classes.
- Icons go to `priv/static/images/`, sound images to `priv/static/images/sounds/`, and mp3s to `priv/static/sounds/`.

---

## 7. Implementation phases

1. **Foundation** (two agents in parallel):
   - **A1, domain**: all Ash resources, migrations, `Campfire.Uploads`, `Campfire.Presence`, `Campfire.Broadcast`,
     webhook delivery, `Campfire.Sound`, and domain tests.
   - **A2, web shell**: remove Tailwind, port CSS and assets, write the root and app layouts, core components and JS hooks.
2. **Features** (two agents in parallel):
   - **B1, auth and admin**: UserAuth, first run, login/logout, join, transfer, profile, user page, account, bots,
     the bot API, avatars and logo.
   - **B2, chat**: sidebar, rooms (create/edit/direct), RoomLive with messages, boosts, uploads, typing, presence,
     search and attachments.
3. **Review and integration**: the lead reviews each phase, merges, runs `mix test`, and smoke-tests in a browser.

Conventions: run `mix format`; `mix compile --warnings-as-errors` must pass; `mix test` must stay green. If the Ash
compile-env error appears after changing config, run `rm -rf _build`.
