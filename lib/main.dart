import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/platform.dart';
import 'core/sfx.dart';
import 'data/local_store.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isWeb) {
    // Path URLs (`/play/<id>`, `/auth/callback`) instead of `/#/play/<id>`,
    // so deep links and the Appwrite OAuth redirect resolve as plain routes.
    usePathUrlStrategy();
  } else {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  }
  final store = await LocalStore.open();
  Sfx.instance.init();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardJigsawApp(),
    ),
  );
}
