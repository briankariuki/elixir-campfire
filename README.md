# Campfire (Elixir)

A port of Basecamp's [Campfire](https://github.com/basecamp/once-campfire) group chat to Elixir:
**Phoenix + LiveView** for the web, **Ash Framework** (with AshPostgres) for the domain.

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
