# Ash review: issues, upgrade plan, and rules for this project

Scope: `lib/campfire/**` (the Ash domain) and how `lib/campfire_web/**` calls it. Versions: Ash 3.34, AshPostgres 2.14,
AshPhoenix 2.3. The yardstick is the official usage rules, now in `.claude/skills/ash-framework/` (synced by
`mix usage_rules.sync`) and linked from `AGENTS.md`.

**Verdict.** The resource and action design is good: specific, well-named actions, policies on every web-facing action,
code interfaces on the domains, and side effects in `after_action`/`after_transaction` hooks. The problem is the
*inside* of those hooks. The port was written "Ash on the outside, Ecto on the inside": 25 places drop to
`Repo`/`Ecto.Query`, every side-effect hook is an anonymous function, and 19 of 20 update/destroy actions switch off
atomic execution. Nothing is broken, but these all bypass what Ash would otherwise give us for free: policies,
notifications, atomicity, and a single place to look for behaviour.

Nothing below is urgent. Items are ordered by value.

---

## 1. Issues

Severity: **H** = bypasses an Ash guarantee (authorization, notifications, atomicity); **M** = non-idiomatic, makes
the next change harder; **L** = cosmetic.

### 1.1 Raw Ecto/Repo queries inside the domain (H)

25 call sites, all in hooks or helpers. They bypass policies, notifiers, and Ash's bulk machinery, and they hard-code
table names and enum strings (`"memberships"`, `"open"`, `"active"`) that the resources already define.

| Where | What it does | Ash replacement |
|---|---|---|
| `chat/message_changes.ex` `mark_unread/1` | `Repo.update_all` on `"memberships"` | `Membership` filter query → `Ash.bulk_update!(:mark_unread, %{unread_at: ...})` with a dedicated atomic update action |
| `chat/message_changes.ex` `touch_room/1` | `Repo.update_all` on `"rooms"` | `Room` update action `:touch` with `change set_attribute(:updated_at, expr(now()))`, or a `belongs_to :room` with `touch`-like after_action calling it |
| `chat/membership.ex` `grant/3` | `Repo.insert_all ... on_conflict: :nothing` | `Ash.bulk_create!(rows, Membership, :grant, upsert?: true, upsert_identity: :unique_room_user, upsert_fields: [])` (empty `upsert_fields` = keep the existing row) |
| `chat/membership.ex` `grant_open_rooms/1`, `member_ids/1` | `Repo.all` on `"rooms"`/memberships | read actions (`Room.open_ids`, `Membership.member_ids`) or `Ash.read!` with `select: [:user_id]` |
| `chat/membership.ex` `revoke/2`, `revoke_all_except_direct/1` | `Repo.delete_all` | `Ash.bulk_destroy!(query, :revoke, %{})` — this also makes the `:revoke` broadcast fire for bulk removals, which today it does **not** (see 1.5) |
| `chat/room_changes.ex` `grant_active_users/3`, `existing_user_ids/1`, `destroy_contents/2` | `Repo.all` on `"users"`/messages | `User` read `:active_ids`; `Message` read with `select: [:attachment_key]` |
| `chat/boost.ex` `room_id/1` | `Repo.one` for the message's room | `has_one`/`belongs_to` traversal: load `message.room_id`, or a calculation `room_id` (`expr(message.room_id)`) |
| `chat/search.ex` `prune/1`, `clear_for/1` | `Repo.delete_all` | `Ash.bulk_destroy!` on a `Search` query (`:clear` becomes a bulk destroy on `recent` filtered by actor) |
| `chat/mentions.ex` `room_members/1` | `Repo.all` join on `"users"` | `Membership` read with `load: [user: [:name]]`, or a `User` read filtered by `exists(memberships, room_id == ^id)` |
| `checks/room_member.ex` | `Repo.exists?`, `Repo.one` | `Ash.exists?(Membership filter, authorize?: false)`; for boosts take the room from the `:message` argument (already a struct) instead of querying again |
| `accounts/user_lifecycle.ex` `deactivate/2`, `ban/2`, `unban/2`, `save_webhook/3`, `ban_session_ips/1` | five `Repo.delete_all`, one `Repo.all` | `Ash.bulk_destroy!` on `Session`/`Search`/`Ban`/`Webhook` queries; `Session` read with `select: [:ip_address]`, `distinct` |
| `accounts.ex` `first_run/1` | `Repo.transaction` + `Repo.rollback` | A generic action `:first_run` on `Account` with `transaction? true` (generic actions can run in a transaction), returning `%{account, user, room}` |

Why it matters beyond style: `Repo.delete_all` on sessions in `deactivate` does not run `Session`'s `:destroy`
action, so the "disconnect user" after_transaction on that action never fires for those rows (it works today only
because `UserLifecycle` *also* calls `Broadcast.disconnect_user/1`). Every duplicated side effect like that is a
future inconsistency.

### 1.2 `require_atomic? false` on nearly every update/destroy (M, sometimes H)

19 of 20 update/destroy actions disable atomic execution. The usage rules say to treat this as a smell. Classifying
the actions:

| Action | Needs it? | Why / what to do instead |
|---|---|---|
| `Message.update`, `Message.destroy` | **No** | Only after_action/after_transaction hooks plus `resolve_mentions` (a before_action that reads `room_id`). Rewrite `resolve_mentions` as a change with an `atomic/3` returning `{:not_atomic, reason}`? No — simpler: keep it non-atomic but *document why* (needs member list). Acceptable. |
| `Membership.mark_read`, `set_involvement` | **No** | Pure attribute sets + after_transaction. Remove the flag. |
| `Membership.revoke`, `Boost.destroy`, `Session.destroy`, `Room.destroy` | **No** for the attribute part | after_transaction hooks don't block atomics. `Room.destroy` has a before_action (reads contents) and needs it. |
| `User.change_role`, `deactivate`, `ban`, `unban` | **Partly** | `change_role` reads `changeset.data.role` → could be `validate attribute_does_not_equal(:role, :bot)` + `set_attribute`, fully atomic. `deactivate` reads the email to mangle it → needs it (or `atomic_update(:email_address, expr(...))` with `fragment`). |
| `User.update_profile`, `update_bot`, `reset_bot_key` | **No** | `DeleteReplacedUpload` reads old data → that one needs it; the others don't. |
| `Room.update_open`, `update_closed` | **Yes** | `validate_not_direct` reads `data.kind`; could be `validate attribute_does_not_equal(:kind, :direct)` (atomic-capable). Then only the member revision after_action remains, which is fine. |
| `Session.touch` | already atomic | the only one. |

Target: remove the flag from ~12 actions, keep it (with a comment) on the ~5 that read the current record.

**Status after Phase 2:** 13 of the 20 flags in `lib/campfire` are gone (20 -> 7). Removed from `Membership.set_involvement`,
`mark_read`, `revoke`, `Boost.destroy`, `Session.destroy`, `Message.destroy`, `Room.update_open`, `update_closed`
(the `NotDirect` validation became `attribute_does_not_equal(:kind, :direct)` and was deleted), `User.change_role`,
`ban`, `unban`, `reset_bot_key`, and `Account.reset_join_code`. The hook-only change modules gained an `atomic/3` that
returns `{:ok, change(...)}`. Remaining flags, each commented in the resource:

| Action | Why it stays |
|---|---|
| `Message.update` | `ResolveMentions` reads the stored `room_id` and needs the room's member list |
| `Room.destroy` | `DestroyContents` reads members and attachment keys before the rows cascade away |
| `Session.touch` | `TouchIfStale` reads the stored `last_active_at` and skips the write when fresh (an atomic version would write on every request) |
| `User.deactivate` | `Deactivate` reads the stored email to mangle it |
| `User.update_profile`, `User.update_bot`, `Account.update` | `DeleteReplacedUpload` reads the stored old key |

### 1.3 Anonymous functions instead of change/validation/preparation modules (M)

42 `change &Mod.fun/2`, `change after_action(&...)`, `validate &...`, `run fn ...` sites. Rules: "Prefer to put code
in its own module and refer to that in changes, preparations, validations". Modules are reusable, testable in
isolation, and can implement `atomic/3` and `batch_change/3`.

Groupings that fall out naturally:

- `Campfire.Chat.Message.Changes.{SetRoom, EnsureClientMessageId, ResolveMentions, AfterCreate, AfterUpdate, AfterDestroy}`
- `Campfire.Chat.Message.Validations.HasContent`
- `Campfire.Chat.Room.Changes.{GrantActiveUsers, ReviseMembers, SetDirectKey, DestroyContents}`
- `Campfire.Accounts.User.Changes.{HashPassword, NormalizeEmail, GrantOpenRooms, SaveWebhook, Deactivate, Ban, Unban}`
- `Campfire.Accounts.User.Preparations.VerifyPassword`
- a single shared `Campfire.Changes.Broadcast` change taking `topic:`/`message:` options (replaces five hand-written
  `after_transaction` broadcast hooks that all look identical)

### 1.4 Hand-rolled PubSub instead of `Ash.Notifier.PubSub` (M)

Every broadcast is an `after_transaction` hook calling `Campfire.Broadcast`. Ash has a built-in notifier that fires
after commit, dedupes inside nested transactions, and supports topic templates and `load:`. The current design was a
deliberate simplification (PORTING.md §4), and the per-user fan-out (`{:room_unread, id}` to every member) can't be
expressed as a static topic template, so this is a *partial* migration:

- **Move to the notifier:** `message_created/updated/deleted` on `"room:<room_id>"`, `boost_created/deleted` (with
  `load: [:booster]` and a `room_id` calculation), `room_read` (`Membership.mark_read`), `sidebar_changed` on
  `set_involvement`.
- **Keep as hooks (or a custom `Ash.Notifier`):** per-member fan-outs (`room_unread`, `room_removed`,
  `sidebar_changed` for all members) and webhooks. A custom notifier module (`Campfire.Notifiers.Members`) implementing
  `notify/1` is the idiomatic home — it still runs after commit and keeps the fan-out out of the actions.

Message *shape* changes: the notifier sends `%Ash.Notifier.Notification{}` (or a `%Phoenix.Socket.Broadcast{}`), not
`{:message_created, msg}`. The LiveViews' `handle_info` clauses change accordingly. Set `broadcast_type :notification`
and match on `%Ash.Notifier.Notification{action: %{name: :create}, data: message}`.

**Status after Phase 3.** Done, with one deviation from the text above: `Campfire.PubSubBroadcaster` translates the
`%Ash.Notifier.Notification{}` back into the existing tuples, so the LiveViews' `handle_info` clauses did not change.
`Message`, `Boost` and `Membership` use `Ash.Notifier.PubSub` (`prefix "room"`/`"user"`, templates `[:room_id]`/
`[:user_id]`, so the topics are the same strings as `Campfire.Broadcast.room_topic/1`/`user_topic/1`). `Boost` gained a
denormalized `room_id` (set by `SetMessage`, backfilled in the migration), which replaced `Boost.room_id/1`. The per-member
fan-outs (`room_unread`, `sidebar_changed` for a room's members, `room_removed` on room destroy) and bot webhooks live in
one custom notifier, `Campfire.Notifiers.Fanout`, attached per action with `notifiers [...]`. `BroadcastAfterCommit`,
`NotifyCreated` and `NotifyMembers` are deleted; no `after_transaction` hook in the domain broadcasts any more.
Notifications from nested actions (the bulk `:revoke` inside `ReviseMembers`) are held until the outer Ash action's
transaction commits, so revoked users get exactly one `room_removed` and `sidebar_changed`. Caveat: Ash only knows
about transactions it opened; inside a raw `Repo.transaction/1` notifications are dropped (with a warning), so wrap
multi-action work in an Ash action or use `return_notifications?: true` and `Ash.Notifier.notify/1`.

### 1.5 Bulk deletes skip action side effects (H)

`Membership.revoke_all_except_direct/1` and `Membership.revoke/2` delete rows with `Repo.delete_all`, so the
`{:room_removed, room_id}` broadcast defined on `Membership.revoke` never fires for those paths; the room/user code
re-implements the broadcast by hand (`RoomChanges.notify_members`, `UserLifecycle.deactivate` doesn't broadcast
`room_removed` at all — a deactivated user with an open tab is only kicked by the socket disconnect). Using
`Ash.bulk_destroy!(query, :revoke, %{}, notify?: true)` makes one definition serve all paths.

### 1.6 Direct `Ash.*` calls and `authorize?: false` in the web layer (M)

Rules: "Avoid direct Ash calls in web modules". Sites:

- `lib/campfire_web/message_body.ex:62` — `User |> Ash.Query.filter(id in ^missing) |> Ash.read!(authorize?: false)` →
  a `Accounts.list_users_by_ids/1` code interface (read action with an `ids` argument, `authorize_if actor_present()`).
- `controllers/avatar_controller.ex:18`, `session_transfer_controller.ex:21` — `Ash.get(User, id, authorize?: false)`
  → `Accounts.get_user_for_avatar/1` (a read action with `authorize_if always()` that selects only
  `name, role, avatar_key`) and `Accounts.get_active_user/1`.
- `controllers/auth_html.ex:132` — `list_users(%{}, authorize?: false, query: [...])` to find "the first admin" →
  `Accounts.first_administrator/0` read action, public.
- `live/room_live.ex:483` — raw `Phoenix.PubSub.broadcast_from` for typing. Acceptable (ephemeral, no resource), but
  belongs in `Campfire.Broadcast.typing/3`.

### 1.7 `authorize?: false` inside the domain (L→M)

31 sites. Most are legitimate internal loads (`Ash.load!(message, @loads, authorize?: false)` after create). Two
patterns to tidy:

- Reads that exist only to avoid policies (`Accounts.get_account!(authorize?: false)` in `CanCreateRooms`,
  `Webhooks`, `first_run`). Better: give `Account.get` a policy of `authorize_if always()` (the account row is not
  secret) and drop the flag.
- `Message.remove_all_by_creator/1` (`Ash.read!` + `Enum.each(&Ash.destroy!)`) → `Ash.bulk_destroy!` with
  `notify?: true, return_errors?: true`.

### 1.8 Actor passed in the wrong place (L)

The rules say to set the actor on the query/changeset, not on the call: `Ash.read!(query, actor: user)` is the
discouraged form. The code mostly goes through code interfaces (fine, they do the right thing), but
`Campfire.Chat.count_messages/2` (`Ash.count(query, opts)`) and the `Pagination` module (`Ash.read!(query, opts)`)
pass `actor:` in opts. Use `Ash.Query.for_read(:read, %{}, actor: ...)` or make `count_messages` a code interface
(`define :count_messages, action: :read, ...` with `Ash.count` via the `:count` interface option is not available;
simplest is an aggregate on `Room`: `count :message_count, :messages`).

### 1.9 Pagination as a generic action running raw queries (M)

`Message.page` is a generic action whose `run` builds three queries by hand. It works, but Ash has keyset pagination
built in: a `read :page` with `pagination keyset?: true, default_limit: 40` and `sort [inserted_at: :asc, id: :asc]`
gives `before`/`after` cursors for free. The `around` mode would stay custom. Low priority (the current code is tested
and fine); listed so nobody re-implements it.

### 1.10 Domain-level plain functions (L)

`Accounts.first_run/1`, `set_up?/0`, `valid_join_code?/1`, `get_session_by_token/1`, `touch_session/2`,
`banned_ip?/1`, `Chat.count_messages/2`. Rules: "Instead of defining functions in the domain, you should be defining
actions and exposing them through code interface calls". Each has a direct mapping: `Account.first_run` (generic
action, transactional), `Account.set_up?` (generic boolean → predicate interface `set_up?`), `Account.valid_join_code?`
(generic with arg), `Session.by_token` already exists (just `define :get_session_by_token, action: :by_token, args: [:token]`),
`Session.touch` (add a `where` condition so the action itself decides staleness), `Ban.banned_ip?` (predicate).

### 1.11 Web forms not using `AshPhoenix.Form` consistently (L)

Only `ProfileLive` and `BotsLive` use `AshPhoenix.Form`. `RoomFormLive`, `AccountLive`, `DirectPickerLive` and the
composer use `to_form(%{})` and call code interfaces with maps. That's acceptable for the composer (one text field),
but the room form would get validation errors and `phx-change` validation for free from
`AshPhoenix.Form.for_create(Room, :create_closed, actor: user)`.

### 1.12 Things that are fine (don't "fix")

- `Campfire.Presence`, `Campfire.Uploads`, `Campfire.Sound`, `Campfire.Webhooks` HTTP delivery:
  these are not data; keeping them as plain modules is correct.
- Policies: every rule in PORTING.md §3 is implemented and tested.
- `custom_statements` for the `search_vector` generated column: exactly what the AshPostgres rules recommend.
- Code interfaces on the domains and `can_*?` helpers used for UI decisions.
- `Ash.Resource.put_metadata` to carry `revoked_user_ids` from an after_action to an after_transaction.

---

## 2. Upgrade plan

Each phase is independently shippable, with the test suite (209 tests) as the safety net. Estimated at one focused
agent per phase.

**Phase 1 — Pure refactor, no behaviour change** (issues 1.1, 1.3, 1.7, 1.8, 1.10)
1. Add the missing small actions: `Membership.grant` (create, upsert), `Membership.mark_unread` (update, atomic),
   `Room.touch`, `User.active_ids`/`by_ids` reads, `Session.ip_addresses`, `Account.first_run`, predicates
   (`set_up?`, `valid_join_code?`, `banned_ip?`).
2. Replace every `Repo`/`Ecto.Query` call with `Ash.read!`/`bulk_create!`/`bulk_update!`/`bulk_destroy!`. Delete the
   `import Ecto.Query` lines; the domain should not compile `Ecto.Query` at all (`grep -rn "Ecto.Query\|Repo\." lib/campfire` → only `repo.ex`).
3. Extract anonymous changes/validations/preparations into modules under `lib/campfire/<domain>/<resource>/changes/`.
4. Move the plain domain functions into actions + `define`s. Update `docs/DOMAIN_API.md`.
5. Done when: `mix test` green, `DOMAIN_API.md` lists no plain functions, grep in step 2 is clean.

**Phase 2 — Atomicity** (issue 1.2)
1. Convert `validate_not_direct`/`change_role` to built-in validations (`attribute_does_not_equal`).
2. Remove `require_atomic? false` where nothing reads `changeset.data`; add a one-line comment where it stays.
3. Done when: ≤5 actions carry the flag, each with a justification.

**Phase 3 — Notifications** (issues 1.4, 1.5)
1. Add `notifiers: [Ash.Notifier.PubSub]` to `Message`, `Boost`, `Membership`, `Room` with `module Campfire.PubSubBroadcaster`
   (a 5-line module with `broadcast/3` calling `Phoenix.PubSub`), `prefix "room"`, `broadcast_type :notification`.
2. Add `Campfire.Notifiers.Members` (`use Ash.Notifier`) for per-member fan-outs; attach with `simple_notifiers`.
3. Switch bulk membership revocation to `Ash.bulk_destroy!(..., notify?: true)` and delete the hand-written fan-out in
   `RoomChanges.notify_members`/`UserLifecycle`.
4. Update `handle_info` clauses in `RoomLive`/`Sidebar` to match `%Ash.Notifier.Notification{}`. Keep
   `Campfire.Broadcast` only for topic names, subscribe helpers, typing and socket disconnect.
5. Turn on `config :ash, :pub_sub, debug?: true` in dev while migrating.
6. Done when: no `after_transaction` hook in the domain calls `Broadcast.*`.

**Phase 4 — Optional plugins** (section 4): AshAuthentication for sessions/bot API keys, AshOban for webhooks and ban
cleanup, AshRateLimiter for login. Each is a separate decision.

Not planned: AshJsonApi for the bot API (would change a public contract), keyset pagination rewrite (1.9).

---

## 3. Do's and don'ts for Ash in this project

**Do**
- Put every read/write behind an action and call it through a domain code interface (`Campfire.Chat.create_message/3`).
  New behaviour = new action (or new argument on an existing one), then `define` it, then document it in
  `docs/DOMAIN_API.md`.
- Pass `actor: current_user` from the web layer on every call. Inside hooks, use the `context` you're given.
- Use `authorize?: false` only for system work (webhook replies, ban cleanup, first run) and say why in a comment.
- Use `Ash.bulk_create/update/destroy` for set-based work (grants, unread marks, cleanup). They run the action's
  changes and notifiers; `Repo.*_all` does not.
- Write changes, validations and preparations as modules (`use Ash.Resource.Change` etc.). Implement `atomic/3`
  when the change can be expressed as an expression.
- Keep `after_action` for same-transaction DB work and `after_transaction`/notifiers for messages, HTTP and files.
- Express rules as policies and reuse them in the UI with `Campfire.Chat.can_*?/2`.
- Run `mix ash.codegen --name <what_changed>` after resource changes; review the migration; commit the snapshot.
- Run `mix usage_rules.sync` after upgrading Ash deps, and read the relevant file under
  `.claude/skills/ash-framework/references/` before touching an unfamiliar feature.
- Test through the code interface, with `authorize?: false` only when authorization isn't the subject.

**Don't**
- Don't `import Ecto.Query` or call `Campfire.Repo` in `lib/campfire/**`. If Ash can't express the query, write a
  generic action with `run` and keep the SQL in one obvious place (and prefer a `fragment` in an Ash filter first).
- Don't hard-code table names or enum strings (`"memberships"`, `"open"`). The resource defines them.
- Don't add `require_atomic? false` reflexively. Ask whether the change reads `changeset.data`; if not, leave it on.
- Don't call `Ash.get/read/load/create` from controllers or LiveViews. If you need it, the domain is missing an action.
- Don't broadcast from inside `after_action` (still in the transaction). Use `after_transaction` or a notifier.
- Don't duplicate a side effect in two places (e.g. disconnecting sockets in both `Session.destroy` and
  `UserLifecycle`). One action owns it; other paths call that action (or a bulk version of it).
- Don't use `Ash.read!(query, actor: user)`; put the actor on the query (`Ash.Query.for_read(:x, %{}, actor: user)`)
  or go through the code interface.
- Don't write validations that duplicate attribute constraints (`allow_nil? false`, `min_length`).
- Don't introduce a new "manager"/"service" module for domain logic. The resource is the module.

---

## 4. Plugins to make it "fully Ash"

Researched against the current ecosystem (October 2026): [hex.pm packages depending on ash](https://hex.pm/packages?search=depends%3Ahexpm%3Aash),
[ash-project on GitHub](https://github.com/orgs/ash-project/repositories?type=all), [Ash README](https://github.com/ash-project/ash).
Install any of them with `mix igniter.install <package>` (Igniter is already a dev dep).

| Package | Fit for Campfire | Recommendation |
|---|---|---|
| **`Ash.Notifier.PubSub`** (built-in) | Replaces the hand-written `after_transaction` broadcasts (issue 1.4). | **Adopt** (Phase 3). |
| **`ash_authentication` 4.15** + **`ash_authentication_phoenix` 2.17** | Password strategy replaces `User.sign_in`/`register`/`hash_password`, `Session` and `UserAuth` plumbing; it ships a `Token` resource, sign-in/registration LiveViews, `on_mount` hooks and routes. The **API key strategy** maps directly onto bot keys (`bot_key` → an `ApiKey` resource with hashed keys and expiry), and **magic link** could replace the 4-hour session-transfer links. Costs: the auth pages are generated (we have custom nametag markup, so we'd keep our templates and only use the strategies), token-based sessions differ from the current DB-row sessions (used today for IP bans — `Ban` would need to record IPs at sign-in instead), and the `user_status`/deactivation flow needs a custom `sign_in` check. | **Adopt if** you want OAuth/magic-link/API-key management; otherwise the current 110-line `UserAuth` is simpler. Good Phase 4 candidate. |
| **`ash_oban` 0.8** (+ Oban) | Webhook delivery, ban cleanup and attachment deletion currently run in `Task.Supervisor` with no retry or persistence (a restart loses in-flight webhooks). AshOban triggers an action per record, with retries, in the same DB. Maps to: `Message` trigger `:deliver_webhooks` on create, `User` trigger `:remove_banned_content` when `status == :banned`. | **Adopt** when reliability matters; it also removes `Campfire.Async` and the `:async_tasks` test switch. |
| **`ash_rate_limiter` 2.0** | Restores the login rate limit (10 per 3 min per IP) that PORTING.md dropped, as a declarative `rate_limit` on `User.sign_in`. Backed by Hammer. | **Adopt** (small, closes a known gap). **Status after Phase 4:** done. `User` uses `AshRateLimiter` with `rate_limit do backend Campfire.Hammer; action :sign_in, limit: 10, per: 3 min` (Hammer ETS backend, started in `Campfire.Application`; single node). `:sign_in` gained an optional `ip_address` argument (`Accounts.sign_in(email, pw, %{ip_address: ip})`); the bucket key is `sign_in/ip/<ip>`, or `sign_in/email/<email>` when no IP is passed (`User.Preparations.SignInRateLimitKey`). Every call counts, failed or successful, and success doesn't reset it (as in Rails). Over the limit the action returns `Ash.Error.Forbidden` wrapping `AshRateLimiter.LimitExceeded`, and `SessionController.create` re-renders the login page with 429 and "Too many requests or unauthorized." |
| **`ash_admin` 1.3** | Push-button admin LiveView over every resource. Useful for ops (inspect bans, sessions, webhooks) without writing pages. | **Adopt for dev/admin-only route**; not a replacement for the Campfire account page. |
| **`ash_paper_trail` 0.6** | Version history for `Message` edits ("edited" indicator, audit of deleted messages) and `Account` setting changes. | Optional; cheap to add to `Message` only. |
| **`ash_archival`** | Soft delete. Would let banned users' messages be hidden instead of destroyed (the original destroys them). | Optional; changes product behaviour — decide first. |
| **`ash_state_machine`** | `User.status` (`active → deactivated/banned → active`) and the allowed transitions are a tiny state machine. | Optional; nice for documenting transitions, marginal otherwise. |
| **`ash_events` 0.6** | Centralised event log with replay. Overkill for a chat app unless an audit trail is required. | Skip. |
| **`ash_cloak`** | Encrypt `bot_token`/`password_hash` at rest. Hashes are already non-reversible; bot tokens could be hashed instead (AshAuthentication's API key strategy does this). | Skip; use hashed API keys instead. |
| **`ash_json_api` 1.7** / **`ash_graphql`** | Would generate a standards-based API over the resources. The bot API is a *fixed public contract* (`curl -d 'Hello' /rooms/:id/:bot_key/messages`, custom JSON shapes), so JSON:API can't replace it. Could sit alongside it as a richer API. | Skip for the bot API; optional as an additional API. |
| **`ash_ai` 0.8/1.0** | Tool calling over actions (an MCP server that can post to rooms), structured outputs, vectorized search over messages. A "bot that is an LLM" fits naturally on top of the webhook design. | Optional/fun; not part of the port. |
| **`cinder` 0.17** | Data table LiveView component with Ash integration; useful for `ash_admin`-style user lists. | Skip. |
| **`usage_rules` 1.2** | Installed. `AGENTS.md` and `.claude/skills/{ash-framework,phoenix-framework}` are generated; re-run `mix usage_rules.sync` after dep upgrades. | **Done.** |

**Status after Phase 4 (AshOban).** Done for webhooks and ban cleanup; `Campfire.Async`, `Campfire.TaskSupervisor` and
the `:async_tasks` switch are gone. Deviations from the table text: (1) neither trigger polls (`scheduler_cron false`);
both are enqueued explicitly with `AshOban.run_trigger/3` after commit, so `:deliver_webhooks` is not "on create" and has
no `where` (the `User` trigger keeps `where status == :banned`, which also stops the job for an unbanned user).
(2) Webhooks run one job per bot (`bot_id` action argument, unique per message and bot) rather than one per message, so a
slow bot doesn't hold up the others. (3) Retries: 3 attempts, but only connection-level failures fail a job; a timeout
posts its failure reply and completes the job, so it is posted exactly once. (4) The worker runs without an actor, so
`Message` and `User` have a `bypass AshOban.Checks.AshObanInteraction` policy. (5) Attachment deletion still runs
inline in `DeleteAttachment` (a file delete, not worth a job). Tests use Oban `testing: :inline`; see `docs/DOMAIN_API.md`.

A minimal "fully Ash" target for this project is: Phases 1–3 above, plus AshRateLimiter and AshOban. AshAuthentication
is the one real architectural fork; the review's recommendation is to decide on it before Phase 4, because it changes
the `Session` model that bans depend on.
