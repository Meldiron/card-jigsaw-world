// Design QA harness: the real app with every backend faked, driven by a scene file on the Mac.
//
//   flutter run -t integration_test/design_qa/harness_main.dart --dart-define=DQA_DIR=<dir> ...
//
// The app polls <dir>/scene.json; whenever it changes, the app is built again from scratch with the
// scene's player, save, league and store, goes to the scene's route, plays its actions, waits for
// pictures, and writes <dir>/ready.json (the scene's nonce, layout errors, the visible texts). A hot
// restart (SIGUSR2 to the `flutter run` pid) replays the current scene with the new code. Not part
// of the app; ~/CJW-design-qa/_harness/dqa.py is the Mac side.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/purchases.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/data/sync/backend.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/purchases.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../test/support/fake_sync.dart' show FakeServer, FakeBackend, FakePrefs, FakeAuth;
import 'fakes.dart';
import 'hooks.dart';
import 'presets.dart';

const dqaDir = String.fromEnvironment('DQA_DIR');
const catalogPath = String.fromEnvironment('DQA_CATALOG', defaultValue: '/Users/matejbaco/CJW-design-qa/_harness/catalog-snapshot.json');
const userId = 'dqa-player';

final generation = DateTime.now().microsecondsSinceEpoch;
final _errors = <String>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  Sfx.instance.init();
  final report = FlutterError.onError;
  FlutterError.onError = (details) {
    _errors.add('${details.exceptionAsString()}\n${details.context ?? ''}'.trim());
    report?.call(details);
  };
  runApp(const DqaRoot());
}

class DqaRoot extends StatefulWidget {
  const DqaRoot({super.key});
  @override
  State<DqaRoot> createState() => _DqaRootState();
}

class _DqaRootState extends State<DqaRoot> {
  Timer? _poll;
  String? _raw;
  ProviderContainer? _container;
  Key _appKey = UniqueKey();
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _check() {
    final f = File('$dqaDir/scene.json');
    if (!f.existsSync()) return;
    final raw = f.readAsStringSync();
    if (raw == _raw || raw.trim().isEmpty) return;
    _raw = raw;
    Map<String, dynamic> scene;
    try {
      scene = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _writeReady({'nonce': null, 'error': 'scene.json: $e'});
      return;
    }
    _load(scene);
  }

  Future<void> _load(Map<String, dynamic> scene) async {
    final run = ++_run;
    _errors.clear();
    // Two frames: the old app (with its global navigator keys) leaves before the new one comes.
    final old = _container;
    setState(() => _container = null);
    await WidgetsBinding.instance.endOfFrame;
    old?.dispose();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final container = await buildContainer(scene);
    if (run != _run) return;
    setState(() {
      _container = container;
      _appKey = UniqueKey();
    });
    await WidgetsBinding.instance.endOfFrame;
    final out = <String, dynamic>{'nonce': scene['nonce'], 'scene': scene['id']};
    try {
      await play(scene, container, () => run != _run);
    } catch (e, st) {
      out['error'] = '$e\n$st';
    }
    if (run != _run) return;
    out['errors'] = [..._errors];
    out['texts'] = [
      for (final t in visibleTexts())
        {'text': t.text, 'rect': [t.rect.left.round(), t.rect.top.round(), t.rect.width.round(), t.rect.height.round()]},
    ];
    _writeReady(out);
  }

  void _writeReady(Map<String, dynamic> data) {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final body = jsonEncode({
      ...data,
      'gen': generation,
      'at': DateTime.now().toIso8601String(),
      'size': [view.physicalSize.width / view.devicePixelRatio, view.physicalSize.height / view.devicePixelRatio],
      'dpr': view.devicePixelRatio,
      'padding': [view.padding.top / view.devicePixelRatio, view.padding.bottom / view.devicePixelRatio],
    });
    final tmp = File('$dqaDir/ready.json.tmp')..writeAsStringSync(body);
    tmp.renameSync('$dqaDir/ready.json');
  }

  @override
  Widget build(BuildContext context) {
    final c = _container;
    if (c == null) return const ColoredBox(color: Colors.black);
    return UncontrolledProviderScope(container: c, child: CardJigsawApp(key: _appKey));
  }
}

Map<String, dynamic>? _snapshot;
Future<Map<String, dynamic>> snapshot() async => _snapshot ??= jsonDecode(await File(catalogPath).readAsString()) as Map<String, dynamic>;
List<Map<String, dynamic>> snapshotRows(Map<String, dynamic> s, String table) => [for (final r in (s['tables'][table]['rows'] as List)) Map<String, dynamic>.from(r as Map)];

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo(this.user, {this.apple = false}) : super(Account(NoClient()));
  final models.User user;
  final bool apple;
  @override
  Future<models.User?> currentUser() async => user;
  @override
  Future<models.User> signInAnonymously() async => user;
  @override
  Future<models.User> markQaGuest(models.User user) async => user;
  @override
  Future<void> signOut() async {}
  @override
  Future<bool> hasAppleIdentity() async => apple;
  @override
  Future<void> updateName(String name) async {}
  @override
  Future<void> updatePrefs(Map<String, dynamic> prefs) async {}
}

ProductDetails _product(String id, String title, double price) =>
    ProductDetails(id: id, title: title, description: '', price: '\$${price.toStringAsFixed(2)}', rawPrice: price, currencyCode: 'USD');

final fakeProducts = <String, ProductDetails>{
  ProductIds.coins1000: _product(ProductIds.coins1000, '1,000 Coins', 0.99),
  ProductIds.coins3000: _product(ProductIds.coins3000, '3,000 Coins', 2.99),
  ProductIds.coins5500: _product(ProductIds.coins5500, '5,500 Coins', 4.99),
  ProductIds.coins12000: _product(ProductIds.coins12000, '12,000 Coins', 9.99),
  ProductIds.tickets5: _product(ProductIds.tickets5, '5 Tickets', 1.99),
  ProductIds.tickets15: _product(ProductIds.tickets15, '15 Tickets', 4.99),
  ProductIds.hints5: _product(ProductIds.hints5, '5 Hints', 0.99),
  ProductIds.hints15: _product(ProductIds.hints15, '15 Hints', 2.99),
  ProductIds.vipMonthly: _product(ProductIds.vipMonthly, 'VIP Monthly', 2.99),
  ProductIds.vipYearly: _product(ProductIds.vipYearly, 'VIP Yearly', 14.99),
};

/// Everything a scene sets: see ~/CJW-design-qa/_harness/README.md.
Future<ProviderContainer> buildContainer(Map<String, dynamic> scene) async {
  final snap = await snapshot();
  final packs = snapshotRows(snap, 'packs');
  final puzzles = snapshotRows(snap, 'puzzles');

  final prefs = FakePrefs();
  prefs.values.addAll({
    'onboarded': scene['onboarded'] ?? true,
    'tutorialSeen': scene['tutorialSeen'] ?? true,
    'themeMode': scene['theme'] ?? 'system',
    'sound': false,
    'music': false,
    'reminderOfferShown': true,
    'giftClaimDays': 3,
  });
  if (scene['introsSeen'] ?? true) prefs.values['unlockIntros'] = jsonEncode({'seen': [for (final u in Unlock.values) u.name]});
  for (final e in ((scene['prefs'] as Map?) ?? const {}).entries) {
    // Relative times work here too ("NOW", "DAYS:-0.003"), written as local ISO strings like LocalStore does.
    final v = e.value;
    prefs.values[e.key as String] = v is String && (v == 'NOW' || v.startsWith('DAYS:'))
        ? (v == 'NOW' ? DateTime.now() : DateTime.now().add(Duration(seconds: (double.parse(v.substring(5)) * 86400).round()))).toIso8601String()
        : v as Object;
  }

  final server = FakeServer();
  // Relative times in overrides: "NOW", "TODAY" (this morning), "DAYS:-2.5".
  dynamic when(dynamic v) {
    if (v is List) return [for (final x in v) when(x)];
    if (v is! String) return v;
    // Quest keys of the scene's day and week: "d:{day}:solve3", "{week}:solve10".
    if (v.contains('{day}') || v.contains('{week}')) return v.replaceAll('{day}', Goals.dayKey(now)).replaceAll('{week}', Goals.weekKey(now));
    if (v == 'NOW') return iso(now);
    if (v == 'TODAY') return iso(DateTime(now.year, now.month, now.day, 0, 5));
    if (v.startsWith('DAYS:')) return iso(now.add(Duration(minutes: (double.parse(v.substring(5)) * 24 * 60).round())));
    if (v.startsWith('HOURS:')) return iso(now.add(Duration(minutes: (double.parse(v.substring(6)) * 60).round())));
    return v;
  }

  final row = {
    ...playerPreset(scene['player'] as String? ?? 'casual', userId),
    for (final e in ((scene['profile'] as Map?) ?? const {}).entries) e.key as String: when(e.value),
  };
  server.profiles[userId] = server.write(null, row, userId);
  final progress = progressPreset(scene['progress'] as String? ?? 'some', packs, puzzles);
  for (final e in ((scene['progressRows'] as Map?) ?? const {}).entries) {
    progress[e.key as String] = {'puzzleId': e.key, for (final f in (e.value as Map).entries) f.key as String: when(f.value)};
  }
  for (final e in progress.entries) {
    final id = deterministicId(userId, e.key);
    server.progress[id] = server.write(null, {...e.value, 'userId': userId, 'puzzleId': e.key}, id);
  }

  final signedIn = scene['signedIn'] == true;
  final user = fakeUser(userId, name: row['displayName'] as String, email: signedIn ? 'player@example.com' : '');
  final me = Profile.fromRow(userId, server.profiles[userId]!);
  final league = scene['league'] == 'empty' ? <Profile>[me] : leaguePlayers(me, count: (scene['leagueSize'] as int?) ?? 60);
  final friends = [
    for (final p in league.take((scene['friends'] as int?) ?? 0))
      if (p.id != userId) Friend(id: 'f-${p.id}', friendId: p.userId, name: p.displayName, avatar: p.avatar),
  ];
  final store = scene['store'] as String? ?? 'up';
  final c = ProviderContainer(overrides: [
    localStoreProvider.overrideWithValue(LocalStore(prefs)),
    syncBackendProvider.overrideWithValue(FakeBackend(server)),
    authProvider.overrideWith(() => FakeAuth(user)),
    authRepositoryProvider.overrideWithValue(_FakeAuthRepo(user, apple: scene['apple'] == true)),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepo(league: league, claims: (row['questsCompleted'] as int?) ?? 0, down: scene['socialDown'] == true)),
    socialRepositoryProvider.overrideWithValue(FakeSocialRepo(
      down: scene['socialDown'] == true,
      friendList: friends,
      blocked: [
        for (final p in league.reversed.take((scene['blocked'] as int?) ?? 0))
          if (p.id != userId) BlockedPlayer(id: 'b-${p.id}', playerId: p.userId, name: p.displayName, avatar: p.avatar),
      ],
      events: {
        for (final e in ((scene['eventProgress'] as Map?) ?? const {}).entries)
          e.key as String: EventProgress.fromRow('ep-${e.key}', {'eventId': e.key, ...Map<String, dynamic>.from(e.value as Map)}),
      },
    )),
    uploadRepositoryProvider.overrideWithValue(FakeUploadRepo([
      for (var i = 0; i < ((scene['myPuzzles'] as int?) ?? 0); i++) MyPuzzle(id: 'my-$i', fileId: 'file-$i', title: i.isEven ? 'Holiday $i' : 'Garden'),
    ])),
    catalogRepositoryProvider.overrideWithValue(FakeCatalogRepo(SnapshotCatalogSource(catalogPath, eventPatches: {
      for (final e in ((scene['eventRows'] as Map?) ?? const {}).entries)
        e.key as String: {for (final f in (e.value as Map).entries) f.key as String: when(f.value)},
    }))),
    storeAvailableProvider.overrideWith((ref) async => store != 'down'),
    productsProvider.overrideWith((ref) async => store == 'down' ? const <String, ProductDetails>{} : fakeProducts),
    if (scene['allOpen'] == true) openFeaturesProvider.overrideWithValue(OpenFeatures.all),
  ]);
  return c;
}

/// Goes to the scene's place and plays its actions.
Future<void> play(Map<String, dynamic> scene, ProviderContainer c, bool Function() cancelled) async {
  try {
    await c.read(profileProvider.future).timeout(const Duration(seconds: 8));
    await c.read(progressProvider.future).timeout(const Duration(seconds: 8));
    await c.read(packsProvider.future).timeout(const Duration(seconds: 15));
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final router = c.read(routerProvider);
  final route = scene['route'] as String?;
  if (route != null) router.go(route);
  for (final p in ((scene['push'] as List?) ?? const [])) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    router.push(p as String);
  }
  await Future<void>.delayed(Duration(milliseconds: (scene['delay'] as int?) ?? 900));
  for (final a in ((scene['actions'] as List?) ?? const [])) {
    if (cancelled()) return;
    await act(Map<String, dynamic>.from(a as Map), c);
  }
  await Future<void>.delayed(Duration(milliseconds: (scene['settle'] as int?) ?? 1200));
  // Pictures: wait (at most 12 s) until nothing is loading.
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(end) && PaintingBinding.instance.imageCache.pendingImageCount > 0) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await WidgetsBinding.instance.endOfFrame;
}

// ---- a small driver: visible texts, taps, scrolls ----

int _viewId() => WidgetsBinding.instance.platformDispatcher.views.first.viewId;

bool _hits(RenderObject ro, Offset p) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, p, _viewId());
  return result.path.any((e) => e.target == ro);
}

class VisibleText {
  VisibleText(this.text, this.rect, this.element);
  final String text;
  final Rect rect;
  final Element element;
}

List<VisibleText> visibleTexts() {
  final out = <VisibleText>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is RichText) {
      final ro = e.renderObject;
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        final rect = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
        if (_hits(ro, rect.center)) out.add(VisibleText(w.text.toPlainText(), rect, e));
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return out;
}

VisibleText? findText(String text, {bool contains = false, int index = 0}) {
  final hits = [for (final t in visibleTexts()) if (contains ? t.text.contains(text) : t.text.trim() == text) t];
  return hits.length > index ? hits[index] : null;
}

int _pointer = 1000;

Future<void> tapAt(Offset p) async {
  final id = _pointer++;
  final b = GestureBinding.instance;
  b.handlePointerEvent(PointerAddedEvent(pointer: id, position: p, viewId: _viewId()));
  b.handlePointerEvent(PointerDownEvent(pointer: id, position: p, viewId: _viewId()));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  b.handlePointerEvent(PointerUpEvent(pointer: id, position: p, viewId: _viewId()));
}

Future<void> dragFrom(Offset from, Offset to, {int ms = 300}) async {
  final id = _pointer++;
  final b = GestureBinding.instance;
  b.handlePointerEvent(PointerDownEvent(pointer: id, position: from, viewId: _viewId()));
  const steps = 12;
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
    final p = Offset.lerp(from, to, i / steps)!;
    b.handlePointerEvent(PointerMoveEvent(pointer: id, position: p, delta: (to - from) / steps.toDouble(), viewId: _viewId()));
  }
  b.handlePointerEvent(PointerUpEvent(pointer: id, position: to, viewId: _viewId()));
}

List<ScrollableState> visibleScrollables(Axis axis) {
  final out = <ScrollableState>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      final ro = e.renderObject;
      if (s.position.axis == axis && ro is RenderBox && ro.attached && ro.hasSize) {
        final rect = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
        final probe = Offset(rect.center.dx, rect.top + rect.height * 0.4);
        if (_hits(ro, probe) || _hits(ro, rect.center)) out.add(s);
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return out;
}

Future<void> act(Map<String, dynamic> a, ProviderContainer c) async {
  Future<void> pause([int? ms]) => Future<void>.delayed(Duration(milliseconds: ms ?? (a['ms'] as int?) ?? 700));
  if (a.containsKey('wait')) return Future<void>.delayed(Duration(milliseconds: a['wait'] as int));
  if (a.containsKey('tap') || a.containsKey('tapContains')) {
    final text = (a['tap'] ?? a['tapContains']) as String;
    VisibleText? t;
    for (var i = 0; i < 20 && t == null; i++) {
      t = findText(text, contains: a.containsKey('tapContains'), index: (a['index'] as int?) ?? 0);
      if (t == null) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (t == null) throw StateError('tap: "$text" not on screen');
    await tapAt(t.rect.center);
    return pause();
  }
  if (a.containsKey('tapAt')) {
    final p = a['tapAt'] as List;
    await tapAt(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
    return pause();
  }
  if (a.containsKey('drag')) {
    final p = a['drag'] as List;
    await dragFrom(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()), Offset((p[2] as num).toDouble(), (p[3] as num).toDouble()));
    return pause();
  }
  if (a.containsKey('scroll') || a.containsKey('hscroll')) {
    final axis = a.containsKey('scroll') ? Axis.vertical : Axis.horizontal;
    final list = visibleScrollables(axis);
    final which = (a['which'] as int?) ?? 0;
    if (list.length <= which) throw StateError('scroll: no scrollable #$which');
    final pos = list[which].position;
    final by = ((a['scroll'] ?? a['hscroll']) as num).toDouble();
    final target = by >= 99999 ? pos.maxScrollExtent : (pos.pixels + by).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.jumpTo(target);
    return pause(400);
  }
  if (a.containsKey('scrollTo')) {
    final text = a['scrollTo'] as String;
    for (var i = 0; i < 40; i++) {
      final t = findText(text, contains: a['contains'] == true);
      if (t != null) {
        await Scrollable.ensureVisible(t.element, alignment: (a['align'] as num?)?.toDouble() ?? 0.3);
        return pause(400);
      }
      final list = visibleScrollables(Axis.vertical);
      if (list.isEmpty) break;
      final pos = list[(a['which'] as int?) ?? 0].position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      pos.jumpTo((pos.pixels + 300).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('scrollTo: "$text" not found');
  }
  if (a.containsKey('back')) {
    await rootNavigatorKey.currentState?.maybePop();
    return pause();
  }
  if (a.containsKey('hook')) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) throw StateError('hook: no navigator');
    final fn = hooks[a['hook']];
    if (fn == null) throw StateError('hook: unknown ${a['hook']}');
    unawaited(fn(ctx, c, Map<String, dynamic>.from((a['args'] as Map?) ?? const {})));
    return pause(900);
  }
  if (a.containsKey('profile')) {
    // A change after the start (e.g. coins rising): applied as the server's answer.
    throw UnimplementedError('profile action');
  }
  throw ArgumentError('unknown action $a');
}
