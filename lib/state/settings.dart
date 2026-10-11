import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../core/sfx.dart';
import '../data/local_store.dart';

final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main'));

enum CardStyle { classic, minimal }

class Settings {
  const Settings({
    required this.themeMode,
    required this.sound,
    required this.music,
    required this.haptics,
    required this.showTimer,
    required this.notifications,
    required this.cardStyle,
    required this.defaultGrid,
    required this.onboarded,
    required this.tutorialSeen,
  });

  final ThemeMode themeMode;
  final bool sound;
  final bool music;
  final bool haptics;
  final bool showTimer;
  final bool notifications;
  final CardStyle cardStyle;
  final int defaultGrid;
  final bool onboarded;
  final bool tutorialSeen;

  Settings copyWith({
    ThemeMode? themeMode,
    bool? sound,
    bool? music,
    bool? haptics,
    bool? showTimer,
    bool? notifications,
    CardStyle? cardStyle,
    int? defaultGrid,
    bool? onboarded,
    bool? tutorialSeen,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        sound: sound ?? this.sound,
        music: music ?? this.music,
        haptics: haptics ?? this.haptics,
        showTimer: showTimer ?? this.showTimer,
        notifications: notifications ?? this.notifications,
        cardStyle: cardStyle ?? this.cardStyle,
        defaultGrid: defaultGrid ?? this.defaultGrid,
        onboarded: onboarded ?? this.onboarded,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
      );
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final s = ref.watch(localStoreProvider);
    final settings = Settings(
      themeMode: switch (s.themeMode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
      sound: s.sound,
      music: s.music,
      haptics: s.haptics,
      showTimer: s.showTimer,
      notifications: s.notifications,
      cardStyle: s.cardStyle == 'minimal' ? CardStyle.minimal : CardStyle.classic,
      defaultGrid: s.defaultGrid,
      onboarded: s.onboarded,
      tutorialSeen: s.tutorialSeen,
    );
    Haptics.enabled = settings.haptics;
    Sfx.instance.soundEnabled = settings.sound;
    Sfx.instance.musicEnabled = settings.music;
    return settings;
  }

  LocalStore get _s => ref.read(localStoreProvider);

  void setThemeMode(ThemeMode m) {
    _s.themeMode = m.name;
    state = state.copyWith(themeMode: m);
  }

  void setSound(bool v) {
    _s.sound = v;
    Sfx.instance.soundEnabled = v;
    state = state.copyWith(sound: v);
  }

  void setMusic(bool v) {
    _s.music = v;
    Sfx.instance.setMusic(v);
    state = state.copyWith(music: v);
  }

  void setHaptics(bool v) {
    _s.haptics = v;
    Haptics.enabled = v;
    state = state.copyWith(haptics: v);
  }

  void setShowTimer(bool v) {
    _s.showTimer = v;
    state = state.copyWith(showTimer: v);
  }

  void setNotifications(bool v) {
    _s.notifications = v;
    state = state.copyWith(notifications: v);
  }

  void setCardStyle(CardStyle v) {
    _s.cardStyle = v.name;
    state = state.copyWith(cardStyle: v);
  }

  void setDefaultGrid(int v) {
    _s.defaultGrid = v;
    state = state.copyWith(defaultGrid: v);
  }

  void setOnboarded() {
    _s.onboarded = true;
    state = state.copyWith(onboarded: true);
  }

  void setTutorialSeen() {
    _s.tutorialSeen = true;
    state = state.copyWith(tutorialSeen: true);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
