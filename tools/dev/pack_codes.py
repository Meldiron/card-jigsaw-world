"""Pack codes: make, list and revoke the codes players redeem in Settings > Redeem a pack code.

  .venv/bin/python tools/dev/pack_codes.py create --pack PACK_ID --uses 5 [--expires 2026-12-31] [--note "..."]
  .venv/bin/python tools/dev/pack_codes.py list [--pack PACK_ID]
  .venv/bin/python tools/dev/pack_codes.py revoke CODE_ROW_ID

A code is 16 characters from an alphabet without look-alikes (no 0/O, 1/I/L), printed as
XXXX-XXXX-XXXX-XXXX; case and dashes do not matter when it is typed. Only its SHA-256 hash is stored
(table `pack_codes`, readable by the server alone), so `create` prints the code once: keep it then.
The server (`/code/redeem` on function `api`) checks it, records the claim in `code_claims` and unlocks the pack. Codes
are made with the key in secrets/appwrite-users-key.txt (rows scope); key values are never printed.
"""
import argparse, datetime, hashlib, os, re, secrets, sys

sys.path.insert(0, os.path.dirname(__file__))
from cjw_admin import Client, q, AppwriteError  # noqa: E402

ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'   # the same as functions/api/src/code.js
LENGTH = 16
TABLE = '/tablesdb/cjw/tables/pack_codes/rows'


def normalise(code):
    return re.sub(r'[^A-Z0-9]', '', code.upper())


def code_hash(code):
    return hashlib.sha256(normalise(code).encode()).hexdigest()


def new_code():
    raw = ''.join(secrets.choice(ALPHABET) for _ in range(LENGTH))
    return '-'.join(raw[i:i + 4] for i in range(0, LENGTH, 4))


def create(c, args):
    pack = c.row('packs', args.pack)
    if pack is None:
        raise SystemExit(f'no pack {args.pack}')
    code = new_code()
    data = {'codeHash': code_hash(code), 'packId': args.pack, 'maxUses': args.uses, 'uses': 0, 'note': args.note or None}
    if args.expires:
        data['expiresAt'] = datetime.datetime.fromisoformat(args.expires).replace(tzinfo=datetime.timezone.utc).isoformat()
    row = c.call('POST', TABLE, body={'rowId': 'unique()', 'data': data})
    print(f"code {code}  ->  {pack['name']} ({args.pack}), {args.uses} use(s){', expires ' + args.expires if args.expires else ''}  [row {row['$id']}]")
    print('The code is not stored anywhere: keep it now.')


def list_codes(c, args):
    queries = [q('equal', 'packId', [args.pack])] if args.pack else []
    for r in c.rows('pack_codes', queries):
        print(f"{r['$id']}  {r['packId']:<36} {r.get('uses', 0)}/{r['maxUses']} used  expires {r.get('expiresAt') or '-':<26} {r.get('note') or ''}")


def revoke(c, args):
    r = c.row('pack_codes', args.row)
    if r is None:
        raise SystemExit(f'no code row {args.row}')
    c.update_row('pack_codes', args.row, {'maxUses': r.get('uses', 0)})
    print(f"revoked {args.row}: no more claims ({r.get('uses', 0)} kept)")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    cr = sub.add_parser('create')
    cr.add_argument('--pack', required=True)
    cr.add_argument('--uses', type=int, required=True)
    cr.add_argument('--expires')
    cr.add_argument('--note')
    ls = sub.add_parser('list')
    ls.add_argument('--pack')
    rv = sub.add_parser('revoke')
    rv.add_argument('row')
    args = p.parse_args()
    c = Client()
    try:
        {'create': create, 'list': list_codes, 'revoke': revoke}[args.cmd](c, args)
    except AppwriteError as e:
        raise SystemExit(f'Appwrite error {e}')


if __name__ == '__main__':
    main()
