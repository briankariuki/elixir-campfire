# Campfire (Elixir)

A port of Basecamp's [Campfire](https://github.com/basecamp/once-campfire) group chat to Elixir:
**Phoenix + LiveView** for the web, **Ash Framework** (with AshPostgres) for the domain.

- [Parity with once-campfire](#parity-with-once-campfire): what matches the original, what differs, what's not ported
- `docs/PORTING.md`: the design and port plan (what was kept, simplified or dropped)
- `docs/DOMAIN_API.md`: the domain functions the web layer calls
- `docs/analysis/`: notes on how the original Rails app works

## Running it

Requirements: Elixir 1.18+, Erlang/OTP 27+, Postgres (dev config: `postgres`/`postgres` on localhost).

```sh
mix setup          # deps, database, assets and seed data
mix phx.server     # http://localhost:4000
```

### Test accounts

`mix setup` runs `priv/repo/seeds.exs`, which creates an account with these people (the password is `secret123` for
everyone):

| Email               | Name          | Role          |
|---------------------|---------------|---------------|
| `alice@example.com` | Alice Admin   | administrator |
| `bob@example.com`   | Bob Builder   | member        |
| `carol@example.com` | Carol Coder   | member        |
| `dave@example.com`  | Dave Designer | member        |

It also adds a bot, **Deploy Bot**, whose key is printed at the end of the seed output (admins can see it at
`/account/bots`). The rooms are:

- **All Talk** and **Design**: open rooms
- **Engineering**: a closed room for Alice, Bob, Carol and the bot
- a direct message between Alice and Bob

The seeds are skipped when an account already exists. Use `mix ecto.reset` to start over with fresh seed data. To
try the setup flow instead, drop the database, run `mix ash.setup`, and visit http://localhost:4000. It goes to
`/first_run`, which creates the account, the first administrator and the "All Talk" room. The seeds refuse to run in
production.

Invite others with the join link on the account page (`/account`).

Admins can inspect data at `/admin` (AshAdmin, signed in as an administrator).

Uploaded files are stored on disk in `priv/uploads` (`UPLOADS_DIR` in production).

## Bots

Admins create bots at `/account/bots`. Each bot gets a key, and the page shows the per-room URLs.

```sh
curl -d 'Hello!' http://localhost:4000/rooms/1/<bot_key>/messages                  # post text
curl -F "attachment=@/path/to/file" http://localhost:4000/rooms/1/<bot_key>/messages # post a file
curl http://localhost:4000/rooms/1/<bot_key>/messages                              # read (JSON)
```

When a bot has a webhook URL, it receives a JSON `POST` each time it is @mentioned, and for every message in a DM with
the bot. A `text/plain` or `text/html` response is posted back as the bot's reply. See `docs/PORTING.md` §5.

## Parity with once-campfire

The port aims for feature parity with [basecamp/once-campfire](https://github.com/basecamp/once-campfire). It reuses
the original's CSS, markup, icons and sounds, and keeps its bot API and webhook contracts.

### Same as the original

| Area | Features |
|---|---|
| Setup and accounts | First run, join link with a regenerable code, sign in (rate limited: 10 per 3 min per IP), session transfer links (4 h) with QR code, profiles (name, email, password, bio, avatar), generated initials avatars |
| Rooms | Open, closed and direct rooms; group Pings; the involvement bell (4 levels, `invisible` hides a room); unread marks that skip people viewing the room; create, edit and delete rooms; the member filter for more than 20 people; restricting room creation to admins; the welcome card with the invite link |
| Messages | Text and one attachment per message. Images show inline (thumbnails, stored dimensions, lightbox); other files have Download and Share. Also: @mentions resolved when saved, 8 quick boosts plus custom boosts, reply with quote and attribution, inline edit and delete, permalinks and copy link, 56 `/play` sounds, link previews (OpenGraph), threaded and first-of-day grouping |
| Composer | Enter to send (Cmd/Ctrl+Enter always), formatting toolbar, @mention autocomplete, per-room drafts, typing indicator, pasted and dropped files (up to 10, one message each), disabled after 5 s offline, ArrowUp to edit your last message |
| Scrolling | Infinite scroll in both directions, the DOM trimmed to 300 messages, permalinks opening at the linked message |
| Search | Full-text search of your rooms with your 10 recent searches |
| Admin | Roles, deactivate, ban (IP bans, plus deleting the user's messages in the background), bots, account name and logo, custom CSS |
| Bots | The same bot API endpoints, status codes, headers and JSON shapes. Webhooks with the same payload: text or attachment replies, and a 7 s timeout reply |
| Other | Translation popups, the incompatible-browser page, `X-Version`/`X-Rev` headers, dark mode |

### Different by design

| Original | This port |
|---|---|
| ActionText rich text (Lexxy editor, HTML) | A plain-text body with a safe Markdown-like subset: bold, italic, strike, highlight, code, code blocks, h1, nested lists, `[text](url)` links, `>` quotes. The toolbar inserts that syntax |
| SQLite with FTS5 | Postgres (AshPostgres), with a generated `tsvector` column for search |
| ActionCable and Turbo Streams, a heartbeat channel and `/rooms/:id/refresh` | Phoenix PubSub and LiveView. A reconnect remounts the page, which replaces the refresh endpoint and the heartbeat |
| Resque and Redis jobs | Oban through AshOban, in the same Postgres: webhook delivery, ban cleanup, link previews |
| ActiveStorage | Files on local disk (`UPLOADS_DIR`); `vix` makes the thumbnails |
| Link previews embedded in the rich text | Stored on the message by a background job, with SSRF guards. The link text stays in the message |
| Turbo's infinite scroll | A small `MessagePager` hook, which avoids a LiveView 1.2 stream-ordering bug |

Additions with no counterpart in the original:
- AshAdmin at `/admin` for administrators
- the `/blocked` page for banned IPs on LiveView sockets
- `TRUST_PROXY_HEADERS` for running behind a proxy
- the Docker Compose and Caddy setup

### Not ported

- **Web Push notifications and the installable app (PWA manifest, service worker).** Without push, the `mentions`, `everything` and `nothing` bell levels change nothing; `invisible` still hides the room.
- **Sentry and the ONCE `Purchaser` licensing.**
- **Video poster thumbnails**, which need `ffmpeg`. Videos play with the browser's controls.
- **Syntax highlighting of code blocks** (highlight.js).

## Layout

```
lib/campfire/            Ash domains: Accounts (account, users, sessions, bans, webhooks)
                         and Chat (rooms, memberships, messages, boosts, searches)
lib/campfire_web/        Phoenix: controllers (auth, bot API, files), LiveViews (rooms, settings),
                         components and UserAuth
assets/css/campfire/     the original Campfire stylesheets (MIT)
assets/js/hooks/         the small LiveView hooks (scrolling, composer, local time, presence, …)
priv/repo/seeds.exs      development data (the test accounts above)
rel/overlays/bin/        release scripts: server, migrate
Dockerfile, docker-compose.yml, Caddyfile   deployment (below)
```

## Deploying with Docker

The `Dockerfile` (from `mix phx.gen.release --docker`) builds a release. `docker-compose.yml` runs it with Postgres
and [Caddy](https://caddyserver.com), which serves HTTPS with an automatic certificate for your domain:

```sh
cp .env.example .env          # set PHX_HOST, SECRET_KEY_BASE (mix phx.gen.secret) and POSTGRES_PASSWORD
docker compose up -d --build
```

Point the domain's DNS at the server and open ports 80 and 443. The app runs pending migrations every time it starts.
The first visit goes to `/first_run` to create the administrator. The seed accounts above are for development only.
With `PHX_HOST=localhost`, Caddy uses a local development certificate.

Data lives in three named volumes: `db` (Postgres), `uploads` (avatars, logos and attachments), and `caddy_data`
(certificates). Back up the first two.

### Environment variables

| Variable              | Required | Description                                                                         |
|-----------------------|----------|-------------------------------------------------------------------------------------|
| `DATABASE_URL`        | yes      | `ecto://USER:PASS@HOST/DATABASE` (set by `docker-compose.yml`)                      |
| `SECRET_KEY_BASE`     | yes      | signs and encrypts cookies; generate with `mix phx.gen.secret`                      |
| `PHX_HOST`            | yes      | the public host name (URLs are generated as `https://PHX_HOST`)                     |
| `UPLOADS_DIR`         | yes      | a persistent directory for uploaded files (`/data/uploads` in the image)            |
| `TRUST_PROXY_HEADERS` | no       | `true` to take the client IP from `X-Forwarded-For` (see below)                     |
| `PORT`                | no       | the HTTP port (default `4000`)                                                      |
| `POOL_SIZE`           | no       | database connections (default `10`)                                                 |
| `ECTO_IPV6`           | no       | `true` to connect to the database over IPv6                                         |

The app expects TLS to be terminated by a reverse proxy. Sessions, the sign-in rate limit and IP bans use the client's
IP address. Behind a proxy, every request appears to come from the proxy, so set `TRUST_PROXY_HEADERS=true` when the
app is reachable **only** through a proxy that overwrites `X-Forwarded-For`. Caddy does this, and `docker-compose.yml`
sets it. Otherwise clients could choose their own IP address.

To run the image without Compose, run `/app/bin/migrate`, then `/app/bin/server` (the default command), with the
variables above and a volume mounted at `/data/uploads`.

## Tests

```sh
mix test
```
