# 01 — Campfire Domain / Business Logic (Rails → Elixir/Ash port)

Source: `once-campfire` (Rails 8, SQLite, ActionText, ActiveStorage, ActionCable/Turbo).
Scope: schema, models, concerns, jobs, `lib/`, relevant initializers, plus the controller/channel code where business rules actually live (a lot of domain logic sits in controllers in this app — it is called out below).

---

## 0. Big picture

- **Single-tenant**: exactly one `Account` row. Everything else is global (no account_id FKs).
- **Users** (roles: member / administrator / bot; status: active / deactivated / banned).
- **Rooms** use STI (`type` column): `Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`.
- **Memberships** join users↔rooms and carry *involvement* (notification level), *unread_at*, and *presence* (`connected_at`, `connections`).
- **Messages** belong to room + creator; body is ActionText rich text (HTML, stored in `action_text_rich_texts`), optional single file attachment (ActiveStorage).
- **Boosts** = short (≤16 chars) reactions on a message.
- **Bots** are users with `role=bot`, authenticate with a `bot_key` in the URL, and optionally have a **Webhook** that receives messages that mention them (or all messages in direct rooms with them). The webhook HTTP response becomes the bot's reply.
- **Search**: SQLite FTS5 virtual table over plain-text message bodies; per-user "recent searches" (max 10).
- **Push**: Web Push (VAPID) subscriptions per user.
- **Bans**: IP bans derived from the banned user's sessions; blocks non-GET requests from those IPs; deletes the user's messages.

---

## 1. Tables & models

All tables have `id` (integer PK), `created_at`, `updated_at` (NOT NULL) unless noted.

### 1.1 `accounts` → `Account`
| column | type | notes |
|---|---|---|
| name | string NOT NULL | FirstRun sets `"Campfire"` |
| join_code | string NOT NULL | generated `before_create` |
| custom_styles | text | admin-editable CSS (raw) |
| settings | json | via `has_json` gem: `restrict_room_creation_to_administrators: false` default |
| singleton_guard | integer NOT NULL default 0, **unique index** | enforces a single row |

- `has_one_attached :logo` (variants `large` 512×512 png, `small` 192×192 png). Fallback stock icons if absent / not variable.
- **Joinable**: `join_code = SecureRandom.alphanumeric(12).scan(/.{4}/).join("-")` → e.g. `CRMu-l8Ge-KB9B` (3 groups of 4 alnum chars). `reset_join_code` regenerates (admin only).
- Settings booleans are coerced from strings (`"true"`/`"false"` → bool). Stored JSON is `{"restrict_room_creation_to_administrators": true}`.
- `Current.account` = `Account.first`.

### 1.2 `users` → `User`
| column | type | notes |
|---|---|---|
| name | string NOT NULL | |
| email_address | string, **unique index** (nullable — bots have none) | |
| password_digest | string (bcrypt) | `has_secure_password validations: false` → **no password validations at all** (very long passwords allowed) |
| role | integer NOT NULL default 0 | enum `member=0, administrator=1, bot=2` |
| status | integer NOT NULL default 0 | enum `active=0, deactivated=1, banned=2` |
| bio | text | |
| bot_token | string, **unique index** | only for bots |

- **No model validations** (uniqueness of email enforced only by DB; controller rescues `RecordNotUnique` → redirect to login with email prefilled).
- Associations: `has_many memberships (delete_all)`, `rooms through memberships`, `reachable_messages` (= messages in rooms the user is a member of), `messages` (as creator, `dependent: destroy`), `push_subscriptions (delete_all)`, `boosts` (as booster, destroy), `searches (delete_all)`, `sessions (destroy)`, `bans (destroy)`, `has_one webhook (delete)`, `has_one_attached avatar` (variant `square` 512×512 webp).
- Scopes: `ordered` = `ORDER BY LOWER(name)`; `filtered_by(q)` = `name LIKE %q%`; `active_bots` = active + role bot; `without_bots` = role != bot; plus enum scopes `active`, `banned`, etc.
- Callback: **`after_create_commit :grant_membership_to_open_rooms`** → insert a membership (default involvement from DB = `"mentions"`) for every `Rooms::Open`. Applies to bots too (`create_bot!` goes through `User.create!`).
- Helpers: `initials` = first letter of each word (`name.scan(/\b\w/).join`); `title` = `"name – bio"` (bio omitted if blank).
- `avatar_token` = signed id (purpose `:avatar`, non-expiring) used in public avatar URLs `/users/:avatar_token/avatar?v=updated_at`. Avatar fallback: SVG with initials (humans) or default bot SVG.
- Mentionable: users are ActionText attachables with content type `application/vnd.campfire.mention`, plain-text representation `"@#{name}"`.

### 1.3 `rooms` → `Room` (STI)
| column | type | notes |
|---|---|---|
| name | string (nullable) | direct rooms have no name |
| type | string NOT NULL | `"Rooms::Open"`, `"Rooms::Closed"`, `"Rooms::Direct"` |
| creator_id | bigint NOT NULL | defaults to `Current.user` (no FK constraint) |

- Associations: `has_many memberships (dependent: delete_all)`, `users through memberships`, `messages (dependent: destroy)`, `belongs_to creator (User)`.
- Validation (update only): **a Direct room's type can never change** (`"can't be changed for a direct room"`). Open ↔ Closed conversion is allowed.
- Scopes: `opens`, `closeds`, `directs`, `without_directs`, `ordered` (`LOWER(name)`), class `original` = oldest room (`order(:created_at).first`) — used as a user's default landing room.
- `default_involvement`: `"mentions"` (Open/Closed), `"everything"` (Direct).

### 1.4 `memberships` → `Membership`
| column | type | notes |
|---|---|---|
| room_id | integer NOT NULL | |
| user_id | integer NOT NULL | |
| involvement | string default `"mentions"` | enum (string-backed, values are the strings themselves): `invisible`, `nothing`, `mentions`, `everything` |
| unread_at | datetime | NULL = read |
| connected_at | datetime | presence heartbeat |
| connections | integer NOT NULL default 0 | open presence subscriptions |

- Unique index `(room_id, user_id)`; indexes on room_id, user_id, `(room_id, created_at)`. No FKs.
- Scopes: `visible` (involvement != invisible), `unread` (unread_at NOT NULL), `connected` (connected_at ≥ now-60s), `disconnected` (connected_at NULL or < now-60s), `with_ordered_room` (join rooms, order LOWER(rooms.name)), `without_direct_rooms`, enum scopes `involved_in_everything` etc.
- Callback: `after_destroy_commit { user.reset_remote_connections }` → forcibly disconnects that user's websocket(s) with reconnect, so channel subscriptions get re-authorized (revoked members stop receiving the room stream).
- `read` → `unread_at = nil`; `unread?`.

### 1.5 `messages` → `Message`
| column | type | notes |
|---|---|---|
| room_id | integer NOT NULL, FK rooms | |
| creator_id | integer NOT NULL, FK users | defaults to `Current.user` |
| client_message_id | string NOT NULL | client-generated UUID for optimistic UI; `before_create` fills `Random.uuid` if blank (bots) |

- Body: `has_rich_text :body` → row in `action_text_rich_texts(record_type='Message', record_id, name='body', body TEXT html)`.
- Attachment: `has_one_attached :attachment` (variant `thumb` resize_to_limit 1200×800; videos get a webp preview). `create_with_attachment!` = `create!` then analyze + generate thumbnail/preview synchronously.
- `belongs_to :room, touch: true` → creating/updating a message bumps `rooms.updated_at` (used to sort direct rooms in sidebar and for refresh). `has_many :boosts, dependent: :destroy`.
- **No validations** besides required belongs_to. (Bot endpoint rejects empty body+no attachment at controller level; human composer is client-validated.)
- Scopes: `ordered` (created_at), presentation preload scopes (ignore), pagination & search (below).
- `plain_text_body` = `body.to_plain_text.presence || attachment.filename || ""` (mentions render as `@Name`).
- `to_key` = `[client_message_id]` (DOM id uses client_message_id).
- `content_type`: `"attachment"` if attached; `"sound"` if plain text matches `/\A\/play (?<name>\w+)\z/` and name is a known Sound; else `"text"`.
- Callbacks: `after_create_commit -> { room.receive(self) }` (unread + push, see §2.5); search index create/update/delete hooks.

### 1.6 `boosts` → `Boost`
| column | type | notes |
|---|---|---|
| message_id | integer NOT NULL, FK | `belongs_to :message, touch: true` (touch cascades to room) |
| booster_id | integer NOT NULL (no FK) | defaults to `Current.user` |
| content | string(16) NOT NULL | free text/emoji, max 16 chars (DB limit + form `maxlength=16`, `pattern=/\S+.*/`) |

- Scope `ordered` (created_at). No uniqueness: a user can add many boosts to one message.

### 1.7 `sessions` → `Session`
| column | type | notes |
|---|---|---|
| user_id | NOT NULL FK | |
| token | string NOT NULL **unique** | `has_secure_token` (24-char base58) |
| ip_address, user_agent | string | |
| last_active_at | datetime NOT NULL | `before_create` sets now |

- `ACTIVITY_REFRESH_RATE = 1.hour`. `resume(user_agent:, ip_address:)`: only if `last_active_at` older than 1h → update ua, ip, last_active_at=now (throttled writes).
- Cookie: `cookies.signed.permanent[:session_token] = token` (httponly, SameSite=Lax). Lookup: `Session.find_by(token:)`. **No expiry** of sessions.

### 1.8 `bans` → `Ban`
| column | type | notes |
|---|---|---|
| user_id | NOT NULL FK | |
| ip_address | string NOT NULL, indexed | |

- Validation: must parse as IP; must not be loopback / private / link-local (`"cannot be a private or internal IP address"`, `"is not a valid IP address"`).
- `Ban.banned?(ip)` = exists with that ip.

### 1.9 `webhooks` → `Webhook`
`user_id` NOT NULL FK, `url` string. One per bot (`has_one`). Delivery logic in §2.10.

### 1.10 `searches` → `Search`
`user_id` NOT NULL FK, `query` string NOT NULL. Scope `ordered` = `updated_at DESC`. See §2.12.

### 1.11 `push_subscriptions` → `Push::Subscription`
`user_id` NOT NULL FK, `endpoint`, `p256dh_key`, `auth_key`, `user_agent`. Index `(endpoint, p256dh_key, auth_key)`.
- Validations: endpoint present; valid URL; `https`; port 443; host is (or is subdomain of) one of `jmt17.google.com, fcm.googleapis.com, updates.push.services.mozilla.com, web.push.apple.com, notify.windows.com`; DNS must resolve to a public IP (SSRF guard, re-checked at delivery and IP pinned).

### 1.12 Framework tables
- `action_text_rich_texts` (message bodies; unique `(record_type, record_id, name)`).
- `active_storage_blobs/attachments/variant_records` (avatars, account logo, message attachments).
- `message_search_index` — FTS5 virtual table `(body, tokenize=porter)`, `rowid = messages.id`.

### 1.13 Non-persisted
- `Sound`: static list of ~56 named sounds (`56k, bell, bezos, bueller, …, yodel`), each with `asset_path "#{name}.mp3"` and either an `image {name,width,height}` or `text` (emoji/text caption). Message `/play <name>` renders as a sound.
- `FirstRun` (§2.14), `Current` (request-scoped session/user/request), `Purchaser` (reads optional `config/purchased_by.yml` — drop), `ApplicationPlatform` (UA sniffing — UI only).

---

## 2. Business logic

### 2.1 Room types & membership granting

**Membership association helpers** (on `room.memberships`):
- `grant_to(users)` → bulk `INSERT` `(room_id, user_id, involvement: room.default_involvement)`; **insert_all skips duplicates** (ON CONFLICT DO NOTHING on the unique index). Must be idempotent in the port — several code paths grant the same user twice.
- `revoke_from(users)` → destroy those memberships (each triggers websocket reset for that user).
- `revise(granted:, revoked:)` → both in a transaction.
- `Room.create_for(attrs, users:)` → transaction: create room, `grant_to(users)`.

**Open rooms** (`Rooms::Open`): visible to everyone.
- `after_save_commit`: if the type *changed to* `Rooms::Open` (i.e. on create, or on conversion Closed→Open) → `grant_to(User.active)` (includes active bots; excludes deactivated/banned).
- New users are added to every open room (User `after_create_commit`, involvement = DB default `mentions`).
- Created via `Rooms::Open.create_for(name, users: current_user)` then the commit hook grants everyone.
- Editing (update) only changes name; saving through the opens controller forces type to Open (that's how Closed→Open conversion happens).

**Closed rooms** (`Rooms::Closed`): explicit member list.
- Create: `Rooms::Closed.create_for(name, users: User.where(id: params[:user_ids]))` — NB the creator is only a member if included in `user_ids` (UI pre-selects them).
- Update: rename, then `revise(granted: User.where(id: user_ids), revoked: room.users.where.not(id: user_ids))`. Saving through closeds controller forces type to Closed (Open→Closed conversion; members not in the list are removed).
- Default room name in "new" forms: `"New room"`.

**Direct rooms** (`Rooms::Direct`): unnamed, singleton per exact user set.
- `find_or_create_for(users)` where users = selected ids **+ current user**. Lookup: any direct room whose member-id set **equals exactly** the requested set (order-insensitive). Else `create_for({}, users:)` with involvement `everything`.
- Port recommendation: store a canonical `member_key` (sorted user ids joined, or hash) on the room with a unique index for O(1) lookup (the Ruby has a FIXME about this).
- Type is immutable; open/closed controllers can't reach direct rooms.
- **Any member of a direct room can delete it** (`ensure_can_administer` overridden to `true`).
- Direct rooms are excluded from deactivation cleanup (a deactivated user keeps direct memberships so history remains).

**Room deletion**: deletes memberships (no callbacks, `delete_all`), destroys messages (→ boosts, search index rows, rich text, attachments). Broadcast removal from sidebars.

**Room creation permission**: if `account.settings.restrict_room_creation_to_administrators` is true, only administrators may create Open/Closed rooms (`403` otherwise). Direct rooms are always allowed.

### 2.2 Involvement (per-membership notification level)

| value | sidebar | unread marking | push |
|---|---|---|---|
| `invisible` | hidden from sidebar | **no** | no |
| `nothing` | shown | yes | no |
| `mentions` (default for open/closed) | shown | yes | only when @mentioned |
| `everything` (default for direct) | shown | yes | every message |

- UI cycles: shared rooms `mentions → everything → nothing → invisible → mentions`; direct rooms `everything → nothing → everything`. (Server accepts any enum value for any room type.)
- Update is via `PUT /rooms/:room_id/involvement?involvement=...` on the current user's own membership. Side effects: if new value is invisible → remove room from user's sidebar; if old value was invisible → add it back (not for direct rooms).

### 2.3 Unread logic

On message create (after commit) `room.receive(message)`:
```ruby
memberships.visible.disconnected.where.not(user: message.creator)
  .update_all(unread_at: message.created_at, updated_at: now)
```
i.e. every member who is **not invisible**, **not currently present in the room** (see §2.4) and **not the author** gets `unread_at = message.created_at`.

Then (in controllers/webhook, via `message.broadcast_create`):
- append the rendered message to the room stream;
- for **every member** of the room (all memberships, incl. invisible & author) broadcast `{"roomId": <id>}` on per-user stream `user_<id>_unreads`. Client marks the room bold in the sidebar unless it's the room currently open.

Marking read: there is no explicit "mark read" action. **Being present clears it**: subscribing to `PresenceChannel` for a room calls `membership.present`, which sets `unread_at = NULL` (plus connection bookkeeping) and broadcasts `{room_id}` on `user_<id>_reads`. (`Membership#read` exists but is unused.)

Push badge count = number of the recipient's memberships with `unread_at NOT NULL`.

### 2.4 Presence / connections

Constants: `CONNECTION_TTL = 60s` (server); client sends `refresh` every **50s** while tab visible; visibility changes debounced **5s**.

- `connected?` ⇔ `connected_at` present and ≥ now − 60s.
- `present` (on PresenceChannel subscribe, and when tab becomes visible again): single UPDATE `connections = connected? ? connections+1 : 1, connected_at = now, unread_at = NULL`.
- `connected`: increment (if `connected?` then +1 else set to 1) and touch `connected_at`.
- `disconnected` (on unsubscribe, and when tab hidden → client sends `absent`): decrement (if `connected?` then −1 else set 0); if `connections < 1` → `connected_at = NULL`.
- `refresh_connection` (client heartbeat): if not `connected?` set connections=1; touch `connected_at`.
- Stale connections expire implicitly via the 60s TTL (scopes compare timestamps; no sweeper).
- On server boot: `Membership.disconnect_all` → all connected rows get `connected_at=NULL, connections=0`.
- Effect: a user actively viewing a room (connected) is neither marked unread nor pushed for messages in that room.
- Typing indicators: `TypingNotificationsChannel` relays `{action: "start"|"stop", user: {id, name}}` to room subscribers (ephemeral; no DB).

### 2.5 Message creation side effects (in order)

Human path `POST /rooms/:room_id/messages` (requires membership; params `body` (HTML), `attachment`, `client_message_id`):
1. `room.messages.create_with_attachment!(params)` → insert message + rich text; touch room.
2. After commit: insert into FTS index (`plain_text_body`); `room.receive`: unread marking (§2.3) + enqueue `Room::PushMessageJob` (§2.9).
3. Attachment analyzed / thumbnail generated synchronously.
4. `broadcast_create`: append to room stream + per-member unread ping.
5. `deliver_webhooks_to_bots`: eligible bots = `room.direct? ? room.users.active_bots : message.mentionees.active_bots`, **excluding the message creator**; for each, if it has a webhook, enqueue `Bot::WebhookJob`.

Bot path (`POST /rooms/:room_id/:bot_key/messages`) is the same `create` (incl. bot→bot webhook fan-out) — see §2.11.

Webhook replies (§2.10) create messages in the model: steps 1–4 happen, **step 5 does not** (so bot replies never trigger webhooks → no loops).

Update (`PATCH`, creator or admin): update body/attachment, reindex search, broadcast replace. No unread/push/webhook.
Destroy (creator or admin): destroy (boosts, index), broadcast remove.

### 2.6 Mentions encoding

Mentions are ActionText attachments embedded in the HTML body:
```html
<action-text-attachment sgid="<signed GlobalID of gid://campfire/User/ID>"
   content-type="application/vnd.campfire.mention"
   content="<span class=&quot;mention&quot; ...><img avatar> David</span>"></action-text-attachment>
```
- `mentionees` = distinct `User` attachables in the body **intersected with the room's users** (non-members mentioned are ignored).
- Plain text representation of a mention is `@Name`.
- A monkeypatch accepts User sgids even with invalid signatures (survives secret-key rotation); non-User sgids must verify.
- Editor autocomplete: `GET /autocompletable/users?query|filter=` → active users (optionally limited to a room's users) whose name `LIKE %q%`, ordered by LOWER(name), 20/page.

**Port recommendation**: don't replicate sgids. Store body as text (or sanitized HTML) with a simple mention token, e.g. `<mention user-id="42">@David</mention>` or `@[David](42)`, and compute `mentioned_user_ids` at write time (filter to room members). Plain text = replace tokens with `@Name`.

### 2.7 Boosts

- `POST /messages/:message_id/boosts` `{boost: {content}}` — message must be in one of the user's rooms (`reachable_messages`). booster = current user. Broadcast append to room stream (target `boosts_message_<client_message_id>`). Touches message → message.updated_at → room.updated_at.
- `DELETE /messages/:message_id/boosts/:id` — **only the booster** may delete their own boost (no admin override). Broadcast remove.
- Bot variants: `POST /rooms/:room_id/:bot_key/messages/:message_id/boosts` with raw body = content (422 if blank; 404 if room/message not reachable); returns 201 + boost JSON. `DELETE …/boosts/:id` own boosts only (404 otherwise).
- Display: content "all emoji" (`/\A(\p{Emoji_Presentation}|\p{Extended_Pictographic}|️)+\z/`) renders larger (same check used for emoji-only messages).

### 2.8 Pagination

`PAGE_SIZE = 40`, order `created_at ASC` (port: order by `(created_at, id)` for stable ties — a test asserts tie stability).
- `last_page` = last 40 (ascending output). `first_page` = first 40.
- `before(m)`: `created_at < m.created_at`; `after(m)`: `created_at > m.created_at`.
- `page_before(m)` = last 40 before m; `page_after(m)` = first 40 after m.
- `page_around(m)` = page_before(m) + [m] + page_after(m) (used for `/rooms/:id/@:message_id` permalinks and search result jumps).
- `page_created_since(t)` = first 40 with `created_at > t`; `page_updated_since(t)` = last 40 with `updated_at > t` (excluding the "new" ones) — used by `/rooms/:id/refresh?since=<epoch ms>` after reconnect.
- `GET /rooms/:room_id/messages?before=<id>|after=<id>` → page (204 if empty).
- Bot index adds headers `X-Total-Count: <room message count>` and `Link: <…/messages?before=<first.id>>; rel="next"` (or `after=<last.id>` if paging forward) only if more exist.

### 2.9 Push notifications

`Room::PushMessageJob(room, message)` → `Room::MessagePusher#push`.
Recipient subscriptions:
```
Push::Subscription JOIN users JOIN memberships
WHERE membership.room = room AND involvement != 'invisible'
  AND disconnected AND membership.user != message.creator
  AND ( involvement = 'everything'
     OR (involvement = 'mentions' AND user_id IN message.mentionees) )
```
Payload:
- Direct room: `{title: creator.name, body: plain_text_body, path: "/rooms/:id"}`
- Shared room: `{title: room.name, body: "#{creator.name}: #{plain_text_body}", path: "/rooms/:id"}`

Wire JSON sent via Web Push (VAPID, subject `mailto:support@37signals.com`, urgency high):
```json
{"title": "...", "options": {"body": "...", "icon": "/account/logo", "data": {"path": "/rooms/1", "badge": <recipient unread membership count>}}}
```
Delivery via a thread pool (50 threads, queue 10k). On `ExpiredSubscription` / OpenSSL error → destroy that subscription. Endpoint re-validated and DNS-pinned at delivery; skipped if not permitted/public.
Subscriptions: `POST /users/me/push_subscriptions` (find existing by endpoint+keys → re-validate+touch, else create with user_agent); delete; "test notification" sends `{title:"Campfire Test", body: <uuid>}`. Logout deletes the subscription whose endpoint is passed in `push_subscription_endpoint`.

### 2.10 Bots & webhooks

- Bot = `User(role: bot, bot_token: SecureRandom.alphanumeric(12))`, no email/password. `bot_key = "#{id}-#{bot_token}"`.
- `create_bot!(name:, avatar:, webhook_url:)` → creates user (+ joins all open rooms via user callback) and webhook if url given. `update_bot!` → update fields; webhook url present ⇒ update or create; blank ⇒ destroy webhook. `reset_bot_key` → new token. Bot "deletion" = `deactivate`. All bot admin endpoints are admin-only (`/account/bots`).
- `authenticate_bot(key)`: `id, token = key.split("-")`; `User.active_bots.find_by(id:, bot_token: token)`.
- Bot key auth only applies to explicitly allowed endpoints (bot message index/create/update/destroy and bot boost create/destroy); all other routes return 403 for bot-key auth. CSRF skipped for bot-key requests. Bot key in URL path is scrubbed from logs (`/rooms/\d+/)\d+-[A-Za-z0-9]+`).

**Webhook delivery** (`Bot::WebhookJob(bot, message)` → `webhook.deliver(message)`):
- `POST <url>` `Content-Type: application/json`, open & read timeout **7s**, no SSRF guard (admin-configured URL; internal URLs allowed). Body:
```json
{
  "user":    {"id": <creator id>, "name": "<creator name>"},
  "room":    {"id": <room id>, "name": "<room name or null>", "path": "/rooms/<room_id>/<bot_key>/messages"},
  "message": {"id": <id>,
              "body": {"html": "<raw rich-text HTML>", "plain": "<plain text with '@<BotName>' removed, trimmed (unicode spaces)>"},
              "path": "/rooms/<room_id>/@<message_id>"}
}
```
- Response handling:
  1. status `200` and content-type `text/html` or `text/plain` → body (forced UTF-8) becomes a **text reply message** from the bot in the same room (even if empty string — quirk).
  2. else, if response has any content-type that maps to a MIME type → body saved as blob `attachment.<ext>` and posted as an **attachment reply** (quirk: this branch does not check the status code).
  3. else nothing.
  - On open/read timeout → bot posts text `"Failed to respond within 7 seconds"`. Other errors propagate (job fails).
  - Replies are created as messages (unread + push + broadcast) but **do not** trigger bot webhooks.

**Bot HTTP API** (format JSON; bot must be a member of the room, else 404):
- `GET /rooms/:room_id/:bot_key/messages[?before|after=id]` → array of message JSON + pagination headers.
- `POST /rooms/:room_id/:bot_key/messages` → raw request body is the message body (treated as HTML/text), or multipart `attachment`; 422 if both blank; `201 Created` + `Location`.
- `PUT/PATCH …/messages/:id`, `DELETE …/messages/:id` (bot must be creator; delete → 204).
- Message JSON: `{id, created_at (UTC), body: {plain_text, html}, creator: {id, name, role, avatar_url}, room: {id}, url}`.
- Boost JSON: `{id, content, created_at, booster: {id, name, role, avatar_url}, message: {id, url}}`.

### 2.11 Users: roles, status, lifecycle

- **Signup** `GET/POST /join/:join_code` (must be unauthenticated; join code must equal account's, else 404): create user (name, email, password, avatar) as `member` → joins all open rooms → new session. Duplicate email → redirect to login.
- **Login**: `User.active.authenticate_by(email, password)` (deactivated/banned can't log in); rate-limit 10 attempts / 3 min; new `Session`.
- **Logout**: destroy session, clear cookie, remove given push subscription, disconnect user's websockets.
- **Role change** (admin, `/account/users/:id`): only `member` or `administrator` (anything else → member). No guard against demoting self/last admin.
- **Profile** (self): name, email, password, bio, avatar.
- **Deactivate** (admin; also used for bots), in a transaction:
  1. close the user's websocket connections;
  2. delete memberships **except direct rooms**;
  3. delete push subscriptions, searches, sessions;
  4. `status = deactivated`, `email_address = email.gsub("@", "-deactivated-#{uuid}@")` (frees the email for re-use).
  Messages are kept. Deactivated users show "X is no longer on this account".
- Account page: admins see active+banned users (non-bots), members see active ones.

### 2.12 Bans (admin only; UI hides for self)

`user.ban` (transaction):
1. for each distinct non-blank `sessions.ip_address` → `bans.create!(ip_address:)` (**raises** if an IP is private/loopback → whole ban rolls back; quirk);
2. close websockets, delete all sessions;
3. enqueue `RemoveBannedContentJob` → destroy **every message** by the user and broadcast removal;
4. `status = banned`.

`user.unban`: delete all the user's bans; `status = active` (messages are not restored).

Enforcement: every non-GET/HEAD request from an IP in `bans` → `429 Too Many Requests` (any user). Banned users also can't log in (not active).

### 2.13 Sessions & transfer links

- See §1.7. Auth precedence per request: session cookie → bot_key param (if endpoint allows bots) → redirect to login (stores return_to).
- Websocket connection auth: same signed cookie; reject otherwise.
- **Transfer link** (log in on another device / admin "get them back in"): `transfer_id = user.signed_id(purpose: :transfer, expires_in: 4.hours)`; URL `/session/transfers/:transfer_id`. `GET` shows a confirm page, `PUT` → `User.active.find_by_transfer_id` → start new session, else 400. Shown on own profile and (for admins) on any active user's page. Port: use `Phoenix.Token.sign(..., max_age: 4h)`.

### 2.14 FirstRun

Available only when **no Account exists** (`/first_run`; login page redirects there if `User.none?`):
1. create Account `name: "Campfire"` (join code generated);
2. create `Rooms::Open` `"All Talk"` with creator = new user (`role: administrator`);
3. grant memberships (idempotent with the open-room and new-user hooks → exactly one membership);
4. start session. Race → `RecordNotUnique` → redirect root.

### 2.15 Search

- Index: on message create/update/destroy, upsert/delete `plain_text_body` in FTS5 (porter stemming: "eel" matches "eels"; HTML tags are not indexed).
- Query sanitation: `params[:q].gsub(/[^[:word:]]/, " ")` (only word chars kept → no FTS operators).
- Results: `current_user.reachable_messages` (rooms the user is a member of) matching query, ordered by created_at, **last 100**.
- Recent searches: `POST /searches` → `searches.record(query)` = `find_or_create_by(query).touch`; on create, keep only the 10 most recently updated per user (delete the rest). Listed `updated_at DESC`. `DELETE /searches/clear` removes all.
- Port: Postgres `tsvector` column (`to_tsvector('english', plain_body)`) + GIN index + `plainto_tsquery`/`websearch_to_tsquery`, or `ILIKE` for simplicity.

### 2.16 Sidebar / navigation rules (domain-adjacent)

- Sidebar: user's **visible** memberships; direct rooms sorted by `room.updated_at DESC`; shared rooms by LOWER(name); plus up to 20 "placeholder" active users (oldest first) the user has no direct room with yet.
- `/rooms` redirects to the user's last room; "last room visited" cookie, fallback to `rooms.original` among user's rooms.
- Real-time sidebar broadcasts: open room create/update → global `:rooms` stream; closed room create/update → each member's `[user, :rooms]` stream; direct room create → each member; room destroy → global remove.

### 2.17 Opengraph unfurl (brief)

`POST /unfurl_link {url}` → fetch HTML (SSRF-guarded, ≤5MB, ≤10 redirects, Twitter/X rewritten to fxtwitter.com) → `{title, url, image, description}` (title/url/description required; image must be jpeg/png/gif/webp). Client embeds it into the message body as an `application/vnd.actiontext.opengraph-embed` attachment (rendered as a link-preview card; plain-text repr is ""). Host validation prevents previews pointing back at the Campfire host.

### 2.18 Misc

- Messages rendered with sanitization (extra allowed tags `s u mark table thead tbody tfoot tr th td`, attr `data-language`), auto-linking, and a filter removing link text when a lone unfurled link exists.
- `/play <sound>` messages render a sound player + image/text.
- Account custom CSS and logo (admin).

---

## 3. Authorization rules

Core predicate (`User::Role`):
```ruby
def can_administer?(record = nil)
  administrator? || self == record&.creator || record&.new_record?
end
```
- Without a record → "is administrator".
- With a record → admin, or record's creator, or record not yet persisted.

| Action | Rule |
|---|---|
| View room / post / read messages | must have a membership in the room (all room-scoped lookups go through `current_user.rooms` / memberships) |
| Create open/closed room | any user, unless `restrict_room_creation_to_administrators` → admins only |
| Create direct room | any user |
| Update open/closed room (rename, members, convert type) | `can_administer?(room)` (admin or creator) and must be a member |
| Delete open/closed room | `can_administer?(room)` |
| Delete direct room | any member |
| Edit/delete message | `can_administer?(message)` (admin or author); bots: author only |
| Boost | any member of the message's room; delete own boosts only |
| Change involvement | own membership only |
| Account settings/name/logo, custom styles, join code reset, user role changes, deactivation, bans, bots mgmt, bot key reset | admin |
| See transfer link of another user, ban button | admin (ban not shown for self) |
| Account edit page view | everyone (admins also see banned users) |
| Room message stream subscription | re-checked against membership at subscribe time; membership removal forces reconnect |
| Bot key requests | only bot-allowed endpoints; bot must be active and a member of the room |
| Banned IP | any non-GET/HEAD → 429 |

---

## 4. Simplify / drop recommendations for the Elixir port

**Keep (core):**
- Account singleton (+ join code, `restrict_room_creation_to_administrators` setting). Use a single row / or app config; keep `join_code` format.
- Users (roles enum, status enum, bcrypt via `bcrypt_elixir`, avatar optional), deactivation semantics (keep the email mangling — it frees the unique email).
- Rooms with a `type` atom enum (`:open | :closed | :direct`) instead of STI; add `direct_key` (sorted member ids) unique-ish for direct lookup.
- Memberships with involvement (store as string/atom enum, default `mentions`; `everything` for direct), `unread_at`, presence (`connected_at`, `connections`) — implement presence with **Phoenix.Presence** instead of DB counters: "connected" = user tracked on topic `room:<id>`. Then unread marking & push filtering use Presence lookups rather than `connected_at`. If keeping DB fields, replicate §2.4 exactly. Clear `unread_at` when user joins the room channel.
- Messages: store `body` as sanitized HTML or plain text/markdown in a `body` text column on `messages` (drop ActionText table), add `plain_body` (for search/push/webhook) and `mentioned_user_ids` (int array). Keep `client_message_id` (needed for optimistic UI dedupe). Single optional attachment (store via local disk/S3 with filename, content_type, byte_size; thumbnails optional — skip or do with `Image`/`vix` later).
- Boosts (content ≤16 chars).
- Sessions table with random token cookie + throttled `last_active_at` (1h). Transfer link via `Phoenix.Token` (4h).
- Bots + webhooks + bot JSON API exactly as §2.10 (payload shape is a public contract). Use Oban (or `Task.Supervisor`) for webhook job; `Req` with 7s timeouts. Consider fixing quirks: only treat 2xx responses; ignore empty text replies.
- Search: Postgres `tsvector` generated column on `plain_body` + GIN index, scoped to user's rooms, last 100; recent searches (10 cap).
- Pagination (40, before/after/around, since-refresh).
- Unread broadcasts via PubSub per-user topics (`user:<id>`), room message broadcasts via `room:<id>` topics.
- Bans (simple): IP list table + plug blocking non-GET; ban = record IPs (skip private IPs instead of raising), kill sessions, delete messages (Oban job), status banned.
- FirstRun flow.

**Simplify:**
- Mentions: replace sgid ActionText attachments with an explicit token format + `mentioned_user_ids` column (see §2.6). Drop the invalid-signature monkeypatch.
- Rich text: allow a small HTML subset or markdown; sanitize with `HtmlSanitizeEx`. Drop the three-layer sanitization pipeline and solo-unfurl filter.
- `grant_to` = `insert_all ... on_conflict: :nothing`. Open-room auto-grant: do it in the create/convert action and in user registration (Ash after_action changes), not in commit callbacks.
- `can_administer?` → Ash policies: `actor.role == :administrator or record.creator_id == actor.id`; direct rooms: any member.
- Websocket "reset remote connections" → broadcast a `disconnect` on the user's socket id (`MyAppWeb.Endpoint.broadcast("users_socket:<id>", "disconnect", %{})`) on membership revoke, deactivate, ban, logout.
- Avatars/logos: store original + serve; generate initials SVG fallback. Skip variants initially.

**Drop (or defer):**
- **Opengraph unfurling** (whole `app/models/opengraph/*`, `UnfurlLinksController`, embed attachment type, SSRF guard library).
- **Web Push** (Push::Subscription, VAPID, pool, endpoint allow-list/DNS pinning) — defer; if kept later, use `web_push_elixir` and reuse the recipient query of §2.9.
- `Purchaser`, `ApplicationPlatform`, browser version gating, version headers, PWA manifest/service worker (unless push kept), Sentry.
- Video previews / image thumbnails (defer).
- Sounds (`/play`) — optional fun feature; trivially portable as a static map if wanted.
- Account custom CSS (optional).
- Typing indicators — trivial with PubSub/Presence; keep only if cheap.
- SQLite FTS5 specifics, `Message::Pagination::Page` preloading wrapper, Turbo stream naming/authorization patches, ActiveStorage direct-upload hardening.
