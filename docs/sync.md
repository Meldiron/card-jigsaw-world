# Save sync

Players use the same save on several devices (the iPhone app and the web site on a laptop, say),
sometimes without a connection. This is how the save stays correct (since 2026-10-13).

## Rules

1. **Send changes, not totals.** Every change to the save is a `SyncOp` (`lib/data/sync/ops.dart`):
   an intent such as "earn 300 coins", "claim quest X", "unlock pack Y for 400 coins", "save this
   board". When it is sent, the op becomes column changes against the row as the server has it:
   Appwrite's atomic operators (`increment`, `decrement` with a floor of 0, `arrayAppend`, …) for
   the profile, so two devices add up instead of overwriting each other.
2. **Queue what cannot be sent.** Ops are stored on the device (`sync.v1.<userId>.ops` in
   SharedPreferences / localStorage) and sent in order by `SyncController` (`lib/state/sync.dart`)
   as soon as the server answers: right away, on a retry timer (2 s to 60 s) while the app is in
   front, on resume and on the next start. The screens show the save with the queued ops applied.
   A device that starts offline keeps playing as the player it last saw (`AuthNotifier` remembers
   it); a device that never reached the server plays as `local`, and its first guest takes that
   play over.
3. **Reload on start, resume, tab focus and sign-in.** The rows are read again (progress
   incrementally from the newest `$updatedAt`). Whatever another device changed is shown once in
   the "Synced from another device" alert (`SyncHost`, never during a game). A purchase on this
   device and a sign-in merge are taken in silently.
4. **Records only improve.** A win keeps the better stars, best moves and best time of the
   server's row and this play; a solved picture stays solved (board saves never touch
   `completed`, and a finish time counts as solved for rows older versions un-solved during a
   replay). Lifetime totals per picture are kept per play-through (`progress.session`), so sending
   the same save twice changes nothing.
5. **Something done twice counts once.** Guarded ops check the fresh row before they are sent: a
   quest, achievement, VIP bonus or daily gift already claimed elsewhere pays nothing; a pack, board
   size or avatar already unlocked elsewhere charges nothing; a piggy bank opened elsewhere pays
   only what is left. Level rewards follow the server's XP, so a level reached on two devices pays
   once; a first solve that turns out to be the second device's pays as a replay.
6. **Coins spent twice are not created.** When the other device spent the balance first, an unlock,
   streak restore or piggy bank opening made here is undone (it is not given away), and a Hint,
   Peek or Magic already used here charges what is left (never below zero). The alert says what
   was not done twice or was undone.
7. **The player picks when the game cannot.** Two different boards in progress for one picture
   (one of them unsent) ask "Two boards in progress" (`BoardChoiceSheet`). An open game whose
   board was continued on another device reloads it with a short "Board updated" alert; a
   different board there asks the same question. Signing in from a guest to an existing account
   asks "Two saves found" when neither save clearly wins, and also when the save that would be
   dropped holds more Coins, Tickets or Hints (`decide` in `lib/state/merge.dart`).

## Exactly once

A request can reach the server and lose its answer. Every profile op appends its id to
`profiles.appliedOps` (event steps to `event_progress.appliedOps`); before an op is sent again (or
on the next fetch) the controller checks that list, so the op is never applied twice. Op ids start
with four characters naming the device (`syncDevice` in its storage): a device removes its own ids
once their ops are confirmed (when it holds more than 20), and any id older than 30 days goes.
Progress ops are idempotent by design (a win recognises its own write by play-through and finish
time). Ledger rows have fixed ids (`<op id>-<n>`). The stored rows are written before the confirmed
op is dropped, so a restart never mistakes this device's own play for another device's.

## Appwrite behaviour the code relies on

Checked against the live backend (Appwrite Cloud 2.4.0) on 2026-10-13 with a QA guest:

- `decrement` below its min and `increment` above its max leave the column unchanged (no error).
- A skipped column does not stop the other columns of the same update.
- `arrayAppend` keeps duplicates; `arrayUnique` and `arrayDiff` work as named. The controller
  tidies duplicates after a sync, and `Profile.fromRow` ignores them.
- `upsertRow` accepts operators, also when it creates the row.
- Passing a nested list to `arrayAppend` stores it and breaks later updates of the row: always pass
  a flat list of strings (`Append` in `lib/data/sync/changes.dart`).

## Columns

`profiles.appliedOps` and `event_progress.appliedOps` (string arrays, 32) and `progress.session`
(string 32), all optional, added 2026-10-13 (Appwrite CLI). Builds before the sync ignore them.

`progress.painting` (boolean, default false, optional), added 2026-10-14 (Appwrite CLI): the board
in progress (or the last one finished) is played in Painting. Board and win ops `Put` it with the
layout, so the flag always describes the saved board; ops queued by older builds carry no flag
and write `false`, and a sign-in merge takes it from the row whose board it keeps. Older builds
ignore it (and resume such a board in colour).

`progress.par` (integer 0-100000, default 0), `progress.peeked` (boolean, default false) and
`progress.bestLock` (integer 0-100000, default 0), all optional, added 2026-10-14 (Appwrite CLI):
the play-through's dealt par, whether Peek was used and the most cards one move of the player's
locked (Magic does not count). The quests read them ("Finish a board at par", "Solve without
Peek", "Lock 5 cards in one move"). Like `painting` they describe the board on the row: board and
win ops `Put` them, a discard clears them, ops queued by older builds write 0 / false, and a
sign-in merge takes them from the row whose board it keeps. A resumed board keeps its saved par
for the quests; the stars still use the par recomputed on resume.

## Known limits

- A guarded op is checked and then written: two devices claiming the same quest within one round
  trip can both be paid. The window is a fraction of a second.
- Two browser tabs of the web site share one queue in localStorage; if both queue changes while
  offline and one closes before the connection returns, its queue can be overwritten by the other.
- The `verify-purchase` function still adds a purchase with a read and a write of the profile row
  (not an operator); a change from the player's device in the same instant can be lost. Switching
  it to operators needs a function redeploy.

## Tests

- `test/sync_test.dart`: two devices on an in-memory server (`test/support/fake_sync.dart`) that
  applies the operators as above: balances add up, unlocks are not lost, offline play survives a
  restart, double claims pay once, a lost answer is not applied twice, the notice, records, board
  conflicts, levels, the `local` hand-over, tidying.
- `integration_test/sync_devices_test.dart`: the app on the simulator is the iPhone, a second
  sync in the same process (own storage, same session) is the laptop, on the live backend:
  `tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart
  --target=integration_test/sync_devices_test.dart -d <udid>` → `screenshots/sync_*.png`.

## Adding a new kind of change

Add a factory and a `case` in `SyncOp` (never rename an existing kind: queued ops are stored by
name), call it from the notifier through `enqueue`, and add a line to `SyncNotice`/`syncNoticeLines`
if players should hear about it from another device. Never write absolute values computed from
the device's copy for anything another device can change.
