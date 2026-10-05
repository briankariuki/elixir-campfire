# Campfire (Elixir)

A port of Basecamp's [Campfire](https://github.com/basecamp/once-campfire) group chat to Elixir:
**Phoenix + LiveView** for the web, **Ash Framework** (with AshPostgres) for the domain.

- `docs/PORTING.md`: the design and port plan (what was kept, simplified or dropped)
- `docs/DOMAIN_API.md`: the domain functions the web layer calls
- `docs/analysis/`: notes on how the original Rails app works

## Running it

Requirements: Elixir 1.18+, Erlang/OTP 27+, Postgres (dev config: `postgres`/`postgres` on localhost).

```sh
mix setup          # deps, database, assets
mix phx.server     # http://localhost:4000
```

The first visit goes to the setup page, which creates the account, the first administrator and the "All Talk" room.
Invite others with the join link on the account page (`/account`).

Admins can inspect data at `/admin` (AshAdmin, signed in as an administrator).

Uploaded files are stored on disk in `priv/uploads` (set `UPLOADS_DIR` in production).

## Bots

Admins create bots at `/account/bots`. Each bot gets a key, and the page shows the per-room URLs.

```sh
curl -d 'Hello!' http://localhost:4000/rooms/1/<bot_key>/messages                  # post text
curl -F "attachment=@/path/to/file" http://localhost:4000/rooms/1/<bot_key>/messages # post a file
curl http://localhost:4000/rooms/1/<bot_key>/messages                              # read (JSON)
```

When a bot has a webhook URL, it receives a JSON `POST` each time it is @mentioned, and for every message in a DM with
the bot. A `text/plain` or `text/html` response is posted back as the bot's reply. See `docs/PORTING.md` §5.

## Layout

```
lib/campfire/            Ash domains: Accounts (account, users, sessions, bans, webhooks)
                         and Chat (rooms, memberships, messages, boosts, searches)
lib/campfire_web/        Phoenix: controllers (auth, bot API, files), LiveViews (rooms, settings),
                         components and UserAuth
assets/css/campfire/     the original Campfire stylesheets (MIT)
assets/js/hooks/         the small LiveView hooks (scrolling, composer, local time, presence, …)
```

## Tests

```sh
mix test
```
