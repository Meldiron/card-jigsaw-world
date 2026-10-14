# Pack codes and hidden packs

A pack code opens a pack that is otherwise hidden: a giveaway on social media, a pack for testers, or
an internal test of art we have not licensed yet. Players type the code in **Settings > Redeem a pack
code** (iPhone and web), or open a link `/redeem?code=ABCD-EFGH-JKMN-PQRS`, which shows the same sheet
with the code filled in.

## Pieces

| Piece | What it does |
| --- | --- |
| `packs.hidden` (boolean) | A hidden pack is listed only for players who have it in `profiles.unlockedPacks` (`Pack.visibleTo`, `packsProvider`, `allPuzzlesProvider`). Hidden pack rows also carry `startAt` 2100-01-01: app builds from before hidden packs treat that as an event that has not opened and never list the pack; this app ignores the dates of a hidden pack. |
| `pack_codes` table (server only, no client permissions) | `codeHash` (SHA-256 of the normalised code, unique index), `packId`, `maxUses`, `uses`, `expiresAt`, `note`. The code itself is never stored. |
| `code_claims` table (server only) | One row per player and code (row id from the code and the player), `codeId`, `userId`, `packId`. A player claims a code once; claiming again just re-opens the pack. Deleted with the player (`delete-account`, `purge_test_players.py`). |
| `redeem-code` function | `POST /redeem {code}` for the signed-in player: checks the code (exists, not expired, uses left), records the claim (the claims count settles a race for the last use), adds the pack to `unlockedPacks` and, for a private pack, grants the player read access to its pictures. Answers `{ok, packId, packName}` or `{ok: false, error: invalid|used|expired|signin|server}`. Execute: users; scopes rows and files read/write. |
| `private-packs` bucket | Pictures of private packs: file security on, no bucket permissions, each file readable only by the players who claimed one of its pack's codes. The app loads them through the signed-in client (`ImageFiles`, like My Puzzles photos), `/view` for boards and `/preview?width=` for tiles and covers. |
| `lib/data/pack_codes.dart`, `lib/features/profile/redeem_code_sheet.dart` | The app side: code format (16 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, typed in any case, dashes optional), the sheet, then a save sync and a catalogue refresh, and the pack opens. |

A hidden pack's rows (name, titles, author) are readable like every catalogue row; only private
pictures are private. Never put anything in a pack name or title that must stay secret.

## Making a pack and codes

```
# A private pack (pictures stay out of the repo and out of the public bucket):
.venv/bin/python tools/dev/private_pack.py create --pack-id pack-x --name "Name" --description "..." \
    --author "Artist" --source "Where it is from, licence" [--source-url URL] [--category Giant] \
    FILE ... [--titles "Title 1" "Title 2" ...]
.venv/bin/python tools/dev/private_pack.py delete --pack-id pack-x

# A code (printed once, only its hash is stored):
.venv/bin/python tools/dev/pack_codes.py create --pack pack-x --uses 5 [--expires 2026-12-31] [--note "..."]
.venv/bin/python tools/dev/pack_codes.py list [--pack pack-x]
.venv/bin/python tools/dev/pack_codes.py revoke ROW_ID
```

A giveaway pack of freely licensed pictures can also be a normal content-tool pack (public pictures)
with `hidden: true` and the far-future `startAt` set on its row; the code then only unlocks and lists
it.

## Current codes

| Pack | Purpose | Uses |
| --- | --- | --- |
| `pack-hidden-object-test` (Hidden Object Adventure, 7 scenes, Giant) | Internal playability test of Cú Xanh's Behance art (all rights reserved, not licensed): private pictures, never public. Delete it if no licence is bought. | 5 (owner) + 2 (QA run) |

QA: `integration_test/pack_codes_test.dart` (pass `--dart-define=QA_PACK_CODE=` with a QA code);
unit tests `test/pack_codes_test.dart`.
