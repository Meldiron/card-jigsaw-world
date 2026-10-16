---
name: inbox-messages
description: Send, list, expire or delete messages in a Carden player's inbox (Social > Inbox), with an optional gift and a button that opens a place in the app. Use for any request to message a player or all players, send a gift or apology, announce something in the app, or look at what a player received.
---

# Inbox messages

Social > Inbox shows messages from Carden to one player (owner, 2026-10-16). Only the owner sends
them, through `tools/dev/inbox.py`; players cannot write. Never send a message on your own
initiative: every send needs the owner's request, and every `--all` send needs the owner's
explicit go for that exact text.

## How it works

- Table `messages` (database `cjw`), one row per player: `userId`, `subject` (120), `body` (text),
  `sentAt` (shown from then on, so a future time schedules it), `expiresAt` (optional; the message
  leaves the inbox after it), `rewardCoins`, `rewardTickets`, `rewardHints`, `rewardPeeks`,
  `rewardMagics` (0 = none), `ctaLabel` (40), `ctaLink` (300). Row permission: `read("user:<id>")`
  only, no table permissions, so the player can read and nobody can change a gift.
- What the player did lives in their profile: `profiles.inbox` holds `seen:<id>`, `claimed:<id>`
  and `deleted:<id>`, written by `SyncOp.inbox` (lib/data/sync/ops.dart). A gift is paid once per
  message on every device (ledger reason `inbox:<id>`).
- The app reads the player's rows on launch, on resume and when the inbox is pulled down
  (lib/state/inbox.dart). An unopened message puts a dot on the Social tab; opening it marks it
  seen. The button says **Claim** while a gift waits, then **Close**. Players can delete messages.
- Deleting an account deletes its messages (`delete-account` function, `PLAYER_TABLES` in
  tools/dev/cjw_admin.py); QA purges remove them too.

## Commands

```
python3 tools/dev/inbox.py send --to <userId> --subject "..." --body "..." [gift] [button] [--expires 7d] [--at ISO] [--yes]
python3 tools/dev/inbox.py send --name "Brave Otter" ...   one player by display name
python3 tools/dev/inbox.py send --all ...                  every player except QA players (one row each)
python3 tools/dev/inbox.py send --qa ...                   the newest QA guest (to check a message)
python3 tools/dev/inbox.py list --to <userId>              messages and their state (seen, claimed, deleted, expired)
python3 tools/dev/inbox.py expire <messageId> --yes        ends a message now
python3 tools/dev/inbox.py delete <messageId> --yes        removes the row
```

Without `--yes` every command is a dry run that prints what it would do. Gift flags: `--coins`,
`--tickets`, `--hints`, `--peeks`, `--magics`; above 10,000 coins, 30 tickets or hints, 50 Peeks
or 20 Magic it refuses unless `--force`. Find a player's user id with `tools/dev/purge_test_players.py
audit` (QA players), the Appwrite console (Auth), a report or feedback row, or `--name`.

## The button (CTA)

`--cta-link` takes any link the app opens (`AppLink.parse`), as a path, `carden://...` or
`https://play.carden.page/...`; `--cta-label` names it (default "Open"). Useful ones:

| Link | Opens |
| --- | --- |
| `/feedback` | Send feedback sheet |
| `/library/pack/<packId>` | a pack |
| `/play/<puzzleId>` | a picture's difficulty screen |
| `/daily` | today's daily puzzle |
| `/events` | Quests (and live events) |
| `/store`, `/vip` | the Store, or its VIP plans |
| `/wheel`, `/gift`, `/piggy` | Lucky Wheel, daily gift, piggy bank |
| `/social?tab=friends`, `/inbox` | Social tabs |
| `/profile/settings`, `/my-puzzles`, `/account` | settings, My Puzzles, sign in |

A new screen needs its link added in `lib/core/app_links.dart` first (docs/deep-links.md).

## Writing them

Follow docs/copy-guide.md: calm, warm, short. The subject says what it is in a few words ("A
thank-you gift", "New pack: Owls at Night"); the body is two or three plain sentences, no hype, no
exclamation marks, no emojis; a gift is named in the body when there is one ("Here are 500 coins
for your next pack."). CTA labels start with a verb and name the place ("Open the pack", "Send
feedback"). Use `--expires` for anything tied to a date (an event, a sale) and leave it off for a
personal note.

## Checking a message on a device

Run a QA build (`tools/dev/qa-run.sh run -d <simulator or chrome>`), then
`python3 tools/dev/inbox.py send --qa --subject ... --yes`, pull down the inbox (or bring the app to
the front) and open it. The QA purge at the end removes the guest and its messages.
