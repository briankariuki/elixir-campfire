# Benchmark seed: the upstream `default` seed in our schema

The upstream benchmark runs every implementation on the same data: the Rails reference app builds a
SQLite database plus an Active Storage directory (the `default` parity seed). `import` converts that
seed to our Postgres schema and uploads layout, keeping the upstream primary keys, so the ids in
`labels.json` (users, rooms, messages, ...) stay valid for the load generator.

| File | What |
|---|---|
| `import` | Converts the upstream seed into `default/` (Python 3 stdlib only: `sqlite3` + `html.parser`) |
| `verify` | Loads `default/` into throwaway containers and checks it (see below) |
| `default/campfire.sql` | Data-only SQL (generated, git-ignored) |
| `default/uploads/` | Files named by our upload keys (generated) |
| `default/labels.json` | Copy of the upstream labels (`table.label` to id, `emails.david`, `passwords.all`, ...) |
| `default/counts.json` | Row counts of the source and of the SQL, and every skipped row |

## 1. Build the upstream seed

In the upstream Rust clone (`.context/bench-src/once-campfire-rust`, which has the Rails `reference/`
submodule), with Docker running:

```sh
parity/bin/reference build          # the campfire-reference image (about 5 minutes)
parity/bin/seed build default       # parity/.seed/default/{db/production.sqlite3, storage/, labels.json}
```

Both run natively on Apple silicon (arm64 images), but the upstream scripts assume GNU userland.
On macOS (bash 3.2, BSD `realpath`) the scratch clone needed two minimal changes, which are not
part of this repo: `mapfile -t x < <(...)` replaced by a `while read` loop in `parity/bin/reference`
and `parity/bin/seed`, and a `realpath` shim that understands `-m` put first on `PATH`
(`.context/bench-src/shims/realpath`). Linux needs neither.

### The seed's sha256

Upstream reports `433ccdce78759eef0524b2840a512077e52cc8e867f6c095430a8871d47a2e38` for
`db/production.sqlite3`. **Our build does not match it, and the file hash can not be compared**:
two consecutive builds on this machine gave different `production.sqlite3` hashes
(`032f948d...`, `fa760682...`) while `sqlite3 production.sqlite3 .dump` and the whole `storage/`
tree were byte-identical between them. The `.dump` of the build used here is
`28505921fb15defc9b7182882ea52e99b75f40cd5e4cea996b38b87efbbedd7c`; compare dumps, not files, if
you need to check that two seeds hold the same data. Content matches the upstream README
(10 users, 11 rooms, 131 messages in the busy room, 14 blobs).

## 2. Import

```sh
bench/seed/import                       # reads .context/bench-src/once-campfire-rust/parity/.seed/default
bench/seed/import --seed DIR --out DIR  # other locations
```

It is deterministic (same input, same `campfire.sql`) and replaces `bench/seed/default/`.
Python was chosen because it ships `sqlite3` and an HTML parser in the standard library, so it needs
no new dependencies in the Elixir app (no `exqlite`), no Ruby, and runs the same on the host and in
the harness container.

### Loading, in this order

1. Migrate a fresh database with the app image: `docker run ... campfire-port:bench /app/bin/migrate`
2. `psql -v ON_ERROR_STOP=1 -q -f campfire.sql` (it has its own `BEGIN`/`COMMIT`, resets the id
   sequences to the imported maximum, and ends with `ANALYZE`)
3. Mount `default/uploads/` as the app's `UPLOADS_DIR` (read-only is enough to serve; the app writes
   new uploads there, so give each run its own copy when benchmarking uploads)

`search_vector` is a generated column and is not inserted. The seed has no Oban jobs.

### `verify`

```sh
docker build -t campfire-port:bench .   # at the repo root
bench/seed/verify
```

Starts Postgres 17, migrates, loads, compares row counts with SQLite, checks every id in
`labels.json`, boots the image on the data, signs in as `labels["emails.david"]` /
`labels["passwords.all"]` and fetches the busy room and three others. Everything is removed
afterwards. Last run: all checks passed.

| Table | SQLite | Postgres |
|---|---:|---:|
| accounts | 1 | 1 |
| users | 10 | 10 |
| rooms | 11 | 11 |
| memberships | 39 | 39 |
| messages | 169 | 168 |
| boosts | 12 | 12 |
| searches | 3 | 3 |
| sessions | 1 | 1 |
| bans | 1 | 1 |
| webhooks | 2 | 2 |
| uploads (files) | 14 blobs (8 used) | 8 |

The benchmark signs in as **david**: `david@37signals.com` / `secret123456`
(`labels.json`: `emails.david`, `passwords.all`; the same password for every human user). The Rails
`$2a$12$` bcrypt digests are copied as they are and verify with our bcrypt (`POST /session` is a 302,
a wrong password a 401). The busy room is `rooms.watercooler` (`486777696`, 131 messages; its page
shows the latest 40), writes go to `rooms.hq`, `messages.busy_060` is the middle page.

## 3. Mapping

| Rails (SQLite) | Ours (Postgres) |
|---|---|
| `accounts` (`singleton_guard`, `join_code`, `name`, `custom_styles`, `settings.restrict_room_creation_to_administrators`) | `accounts` same columns; `logo` attachment to `logo_key` + file (the seed has none) |
| `users.password_digest` | `password_hash` (bcrypt, unchanged) |
| `users.role` 0/1/2 | `role` `member`/`administrator`/`bot` |
| `users.status` 0/1/2 | `status` `active`/`deactivated`/`banned` |
| `users.bot_token`, `bio`, `email_address` | same; `avatar` attachment to `avatar_key` + file; `last_room_id` NULL |
| `rooms.type` `Rooms::Open/Closed/Direct` | `kind` `open`/`closed`/`direct`; `direct_key` = sorted member ids joined by `-`; `creator_id` |
| `memberships` (`involvement`, `unread_at`) | same; `connected_at`/`connections` dropped (presence is in memory here) |
| `messages` + `action_text_rich_texts.body` (HTML) | `messages.body` (Markdown-like text, below) + `mentioned_user_ids` + `embed` |
| `messages.client_message_id` | same |
| `active_storage_attachments` (`Message`/`attachment`) + blob | `attachment_key` (`<blob key><ext>`), `attachment_filename`, `attachment_content_type`, `attachment_byte_size`; `attachment_width/height` from the blob metadata for png/jpeg/webp/gif; `attachment_thumbnail_key` = the same-format Active Storage variant, only for images larger than 1200x800 (as the app does) |
| `boosts` | `boosts` plus `room_id` from the message |
| `searches`, `sessions`, `bans`, `webhooks` | same columns |
| `created_at` | `inserted_at` |

Blob files are read from `storage/<k[0:2]>/<k[2:4]>/<k>` and written to `uploads/<k><ext>`, where
`<ext>` follows `Campfire.Uploads` (lowercase extension of the filename).

### Body conversion

Active Storage HTML becomes the plain text our renderer (`CampfireWeb.MessageBody`) understands:
`<strong>`/`<b>` to `**x**`, `<em>`/`<i>` to `*x*`, `<s>`/`<del>` to `~~x~~`, `<mark>` to `==x==`,
`<code>` to backticks, `<blockquote>` to `> ` lines, `<pre>` to a fenced block (with
`data-language`), `<ul>`/`<ol>` (nested, 2 spaces per level) to `- `/`1. `, headings to `# `,
`<br>` to a newline, `<p>`/`<div>` to lines (blank line between paragraphs), `<a>` to `[text](url)`
or the bare URL when the text is the URL. Mention attachments
(`application/vnd.campfire.mention`; the User id is read from the SGID, the signature is not
checked) become `@Full Name` and the id goes into `mentioned_user_ids`. Opengraph embeds
(`application/vnd.actiontext.opengraph-embed`, both the Lexxy `content` HTML and the Trix attribute
form) become the `embed` map (`url`, `title`, `description`, `image_url`, `site_name` null) and
leave the link text in the body.

## 4. Lossy conversions

- **`messages.unrenderable` (`933434637`, in room `broken`) is skipped**: its author row does not
  exist (`creator_id` 999999), which our foreign key (and the app) can not represent. Messages:
  169 to 168; the `broken` room is empty here. Nothing else is skipped.
- Dropped, because we have no such table or column: `push_subscriptions` (5 rows),
  `memberships.connected_at/connections`, `accounts.settings` other than the room-creation flag,
  `message_search_index` (our `search_vector` is generated from the body), Active Storage variant and
  preview records other than the thumbnails above (the video's webp poster and the `:square` avatar
  variants).
- Rich text we can not express: the table (rows become `a | b | c` lines), `<u>` (text only), `<h2>`
  (rendered as our only heading, `# `), `<mark>` becomes `==` (renders as `<mark>`), the Trix-era
  `og-embed--twitter-avatar` class (the embed keeps its avatar URL, but is drawn as an ordinary card).
- The "Marshal-era" mention (`mention_marshal`, whose SGID upstream treats as invalid) is converted to
  a real mention of David; upstream renders it as plain text.
- Embed cards come from the seed's stored HTML, not a fetch: their `https://example.com/...` images
  do not resolve, as upstream (the harness answers them there).
- `last_room_id` is NULL (Rails has no such column), sessions keep their token but Rails cookies are
  not valid in our app (sign in again; the benchmark does).
- The `.mov` attachment keeps `video/quicktime` and no dimensions or poster.
- Timestamps are copied as written (UTC); the seed's clock is 2026-03-02 16:00 UTC, our app uses the
  real clock, so "unread since" and relative dates differ from upstream's frozen-clock screens.
