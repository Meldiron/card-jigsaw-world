// Friend gifts (owner, 2026-10-17; docs/friend-gifts.md): on a friend's profile a player sends
// that friend 1 ticket or 150 coins. It costs the sender nothing; one gift per friend per day.
// Moved from the send-gift function, which stays deployed for builds up to 124 (docs/functions.md).
//
// Route (function `api`, see main.js):
//   POST /gift/send  { friendId, kind: 'tickets' | 'coins', utcOffset }  called by the app
//
// Only the caller sends (x-appwrite-user-id, set by Appwrite). In order: the caller has the friend
// in their friends list, neither player blocked the other, and the friend's profile exists; the
// caller has sent fewer than DAILY_SENDS gifts today (`limit` otherwise); the gift row (`gifts`, id
// from sender, friend and the sender's calendar day) is created, which fails when today's gift to
// this friend is already sent; then the friend's inbox message (`messages`, readable only by the
// friend, expiresAt = sentAt + 24 h, the reward claimed through the inbox's own flow) and finally a
// push through Appwrite Messaging to the friend's push targets, whose tap opens that message: only
// when the friend has the sender in their friends list too, and at most PUSHES_PER_DAY in 24 hours
// (`shouldPush`; later gifts arrive quietly). A message that cannot be written takes the gift row
// back, so the sender can try again; a push that fails changes nothing (the inbox still has the gift).
// Names go through the name filter (offensive words, links, @handles, domains show as "Player").
import { Client, TablesDB, Messaging, Query, Permission, Role, ID } from 'node-appwrite';
import { DAILY_SENDS, KINDS, LIFETIME_MS, USER_ID, clampOffset, giftCopy, giftDay, giftRowId, messageLink, shouldPush, shownName } from './gift.js';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), messaging: new Messaging(client) };
}

const gone = (e) => e?.code === 404;
const exists = (e) => e?.code === 409;

async function getRow(tables, tableId, rowId) {
  try {
    return await tables.getRow({ databaseId: DB, tableId, rowId });
  } catch (e) {
    if (gone(e)) return null;
    throw e;
  }
}

/// Whether any row of [tableId] matches every [pairs] column = value.
async function any(tables, tableId, pairs) {
  const page = await tables.listRows({
    databaseId: DB,
    tableId,
    queries: [...Object.entries(pairs).map(([k, v]) => Query.equal(k, v)), Query.select(['$id']), Query.limit(1)],
    total: false,
  });
  return page.rows.length > 0;
}

/// How many rows of [tableId] match [queries] (Appwrite counts them; one row is read).
async function count(tables, tableId, queries) {
  const page = await tables.listRows({ databaseId: DB, tableId, queries: [...queries, Query.select(['$id']), Query.limit(1)] });
  return page.total;
}

/// Appwrite keeps every push it sends (title, body, recipient) in its messaging log. Each send
/// deletes gift pushes older than a day from it, so the log never holds a gift for long; other
/// messages (sent from the console) are left alone.
async function cleanupPushLog(messaging, log) {
  try {
    const old = new Date(Date.now() - LIFETIME_MS).toISOString();
    const page = await messaging.listMessages({ queries: [Query.lessThan('$createdAt', old), Query.orderAsc('$createdAt'), Query.limit(100)], total: false });
    let deleted = 0;
    for (const m of page.messages) {
      // A gift push is recognised by its link.
      if (!String(m.data?.data?.link ?? '').startsWith('/inbox?message=')) continue;
      await messaging.delete({ messageId: m.$id });
      deleted++;
    }
    if (deleted) log(`push log: ${deleted} old gift push(es) deleted`);
  } catch (e) {
    log(`push log cleanup: ${e.message}`);
  }
}

function parseBody(req) {
  try {
    return typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
  } catch (_) {
    return {};
  }
}

async function handleSend(req, res, log, error) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, error: 'signin' }, 401);
  const body = parseBody(req) || {};
  const friendId = String(body.friendId ?? '');
  const kind = String(body.kind ?? '');
  if (!USER_ID.test(friendId) || friendId === userId) return res.json({ ok: false, error: 'not-friend' }, 400);
  if (!KINDS[kind]) return res.json({ ok: false, error: 'kind' }, 400);
  const { tables, messaging } = services(req);

  if (!(await any(tables, 'friends', { userId, friendId }))) return res.json({ ok: false, error: 'not-friend' }, 403);
  const [blockedByMe, blockedMe] = await Promise.all([
    any(tables, 'blocks', { blockerId: userId, blockedId: friendId }),
    any(tables, 'blocks', { blockerId: friendId, blockedId: userId }),
  ]);
  const [sender, recipient] = await Promise.all([getRow(tables, 'profiles', userId), getRow(tables, 'profiles', friendId)]);
  // A block either way, or a friend who deleted their account: the same calm "could not send".
  if (blockedByMe || blockedMe || !recipient) return res.json({ ok: false, error: 'unavailable' }, 403);

  const friendName = shownName(recipient.displayName);
  const name = shownName(sender?.displayName);
  const now = new Date();
  const offset = clampOffset(body.utcOffset);
  const day = giftDay(now, offset);
  const giftId = giftRowId(userId, friendId, day);
  const messageId = ID.unique();
  const gift = KINDS[kind];
  const isTest = sender?.isTest === true || recipient.isTest === true;

  if ((await count(tables, 'gifts', [Query.equal('senderId', [userId]), Query.equal('day', [day])])) >= DAILY_SENDS) {
    log(`gift limit: ${userId} sent ${DAILY_SENDS} on ${day}`);
    return res.json({ ok: false, error: 'limit', friendName, day }, 429);
  }

  try {
    await tables.createRow({
      databaseId: DB,
      tableId: 'gifts',
      rowId: giftId,
      data: { senderId: userId, recipientId: friendId, day, kind, amount: gift.amount, messageId, sentAt: now.toISOString(), isTest },
      // The sender reads it to show "Next gift tomorrow"; nobody can change it.
      permissions: [Permission.read(Role.user(userId))],
    });
  } catch (e) {
    if (exists(e)) return res.json({ ok: false, error: 'already', friendName, day });
    throw e;
  }

  const copy = giftCopy(kind, name);
  try {
    await tables.createRow({
      databaseId: DB,
      tableId: 'messages',
      rowId: messageId,
      data: {
        userId: friendId,
        subject: copy.subject,
        body: copy.body,
        sentAt: now.toISOString(),
        expiresAt: new Date(now.getTime() + LIFETIME_MS).toISOString(),
        [gift.column]: gift.amount,
        fromUserId: userId,
        fromName: name,
        fromAvatar: String(sender?.avatar ?? '').slice(0, 64) || null,
      },
      permissions: [Permission.read(Role.user(friendId))],
    });
  } catch (e) {
    try {
      await tables.deleteRow({ databaseId: DB, tableId: 'gifts', rowId: giftId });
    } catch (_) {}
    throw e;
  }

  // The friend's iPhones (every push target of the user; the web has none), when they may get one.
  let pushed = false;
  const [mutual, received] = await Promise.all([
    any(tables, 'friends', { userId: friendId, friendId: userId }),
    count(tables, 'gifts', [Query.equal('recipientId', [friendId]), Query.greaterThan('sentAt', new Date(now.getTime() - LIFETIME_MS).toISOString())]),
  ]);
  if (shouldPush({ mutual, received })) {
    try {
      await messaging.createPush({
        messageId: ID.unique(),
        title: copy.pushTitle,
        body: copy.pushBody,
        users: [friendId],
        data: { link: messageLink(messageId) },
        sound: 'default',
      });
      pushed = true;
    } catch (e) {
      log(`push to ${friendId} not sent: ${e.message}`);
    }
    await cleanupPushLog(messaging, log);
  } else {
    log(`no push to ${friendId}: ${mutual ? `${received} gifts in 24 h` : 'not a mutual friend'}`);
  }
  log(`gift ${kind} ${userId} -> ${friendId} day ${day} (offset ${offset}) message ${messageId} pushed ${pushed}${isTest ? ' [test]' : ''}`);
  return res.json({ ok: true, kind, amount: gift.amount, friendName, day, messageId, pushed });
}

export async function sendGift({ req, res, log, error }) {
  try {
    return await handleSend(req, res, log, error);
  } catch (e) {
    error(e.stack || e.message);
    return res.json({ ok: false, error: 'server' }, 500);
  }
}
