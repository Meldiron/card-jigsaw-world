import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small typed wrapper over SharedPreferences for settings and offline caches.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  // ---- settings ----
  String get themeMode => _prefs.getString('themeMode') ?? 'system';
  set themeMode(String v) => _prefs.setString('themeMode', v);
  bool get sound => _prefs.getBool('sound') ?? true;
  set sound(bool v) => _prefs.setBool('sound', v);
  bool get music => _prefs.getBool('music') ?? true;
  set music(bool v) => _prefs.setBool('music', v);
  bool get haptics => _prefs.getBool('haptics') ?? true;
  set haptics(bool v) => _prefs.setBool('haptics', v);
  bool get showTimer => _prefs.getBool('showTimer') ?? true;
  set showTimer(bool v) => _prefs.setBool('showTimer', v);
  /// Daily reminders, off until the player turns them on (the old
  /// `notifications` key defaulted to on but never scheduled anything).
  bool get reminders => _prefs.getBool('reminders') ?? false;
  set reminders(bool v) => _prefs.setBool('reminders', v);
  /// Reminder time in minutes after local midnight (19:00 by default).
  int get reminderMinutes => _prefs.getInt('reminderMinutes') ?? 19 * 60;
  set reminderMinutes(int v) => _prefs.setInt('reminderMinutes', v);
  String get cardStyle => _prefs.getString('cardStyle') ?? 'classic';
  set cardStyle(String v) => _prefs.setString('cardStyle', v);
  int get defaultGrid => _prefs.getInt('defaultGrid') ?? 4;
  set defaultGrid(int v) => _prefs.setInt('defaultGrid', v);
  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  set onboarded(bool v) => _prefs.setBool('onboarded', v);
  bool get tutorialSeen => _prefs.getBool('tutorialSeen') ?? false;
  set tutorialSeen(bool v) => _prefs.setBool('tutorialSeen', v);

  // ---- house ads ----
  int get completionsSinceAd => _prefs.getInt('completionsSinceAd') ?? 0;
  set completionsSinceAd(int v) => _prefs.setInt('completionsSinceAd', v);
  int get lifetimeCompletions => _prefs.getInt('lifetimeCompletions') ?? 0;
  set lifetimeCompletions(int v) => _prefs.setInt('lifetimeCompletions', v);
  DateTime? get lastInterstitialAt {
    final v = _prefs.getString('lastInterstitialAt');
    return v == null ? null : DateTime.tryParse(v);
  }
  set lastInterstitialAt(DateTime? v) => v == null ? _prefs.remove('lastInterstitialAt') : _prefs.setString('lastInterstitialAt', v.toIso8601String());
  DateTime? get lastRewardedAt {
    final v = _prefs.getString('lastRewardedAt');
    return v == null ? null : DateTime.tryParse(v);
  }
  set lastRewardedAt(DateTime? v) => v == null ? _prefs.remove('lastRewardedAt') : _prefs.setString('lastRewardedAt', v.toIso8601String());
  String? get lastCreativeId => _prefs.getString('lastCreativeId');
  set lastCreativeId(String? v) => v == null ? _prefs.remove('lastCreativeId') : _prefs.setString('lastCreativeId', v);

  // ---- small values ----
  String? getText(String key) => _prefs.getString(key);
  Future<void> setText(String key, String value) => _prefs.setString(key, value);

  // ---- caches ----
  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) => _prefs.setString(key, jsonEncode(value));
  List<dynamic>? getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJsonList(String key, List<dynamic> value) => _prefs.setString(key, jsonEncode(value));
  Future<void> remove(String key) => _prefs.remove(key);
}
