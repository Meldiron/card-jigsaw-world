import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../core/sfx.dart';
import '../data/local_store.dart';

final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main'));

enum CardStyle { classic, minimal }

/// Settings > Accessibility: text size. [standard] follows the iPhone's text size within the
/// app's usual range; the others are fixed sizes for players who need them (Apple's Larger Text:
/// at least 200%).
enum TextSize {
  standard(null, 'Default'),
  large(1.5, 'Large'),
  largest(2.0, 'Largest');

  const TextSize(this.scale, this.label);

  /// The text scale, or null for the usual range.
  final double? scale;
  final String label;
}

/// Settings > Accessibility (owner, 2026-10-16). Every option is off until the player turns it on
/// here, so the usual game is unchanged; the iPhone's own accessibility switches do not turn them
/// on. Kept on the device, like the other settings.
@immutable
class Accessibility {
  const Accessibility({
    this.textSize = TextSize.standard,
    this.reduceMotion = false,
    this.increaseContrast = false,
    this.differentiateWithoutColour = false,
  });

  final TextSize textSize;

  /// No spinning, zooming, sliding or looping motion: cross-fades instead (Apple's Reduced Motion).
  final bool reduceMotion;

  /// Stronger text and outline colours and solid surfaces instead of glass (Sufficient Contrast).
  final bool increaseContrast;

  /// A symbol or text next to every state that colour alone shows (Differentiate Without Color).
  final bool differentiateWithoutColour;

  bool get isDefault => this == const Accessibility();

  factory Accessibility.fromJson(Map<String, dynamic>? j) => Accessibility(
        textSize: TextSize.values.where((v) => v.name == j?['textSize']).firstOrNull ?? TextSize.standard,
        reduceMotion: j?['reduceMotion'] == true,
        increaseContrast: j?['increaseContrast'] == true,
        differentiateWithoutColour: j?['differentiateWithoutColour'] == true,
      );

  Map<String, dynamic> toJson() => {
        'textSize': textSize.name,
        'reduceMotion': reduceMotion,
        'increaseContrast': increaseContrast,
        'differentiateWithoutColour': differentiateWithoutColour,
      };

  Accessibility copyWith({TextSize? textSize, bool? reduceMotion, bool? increaseContrast, bool? differentiateWithoutColour}) => Accessibility(
        textSize: textSize ?? this.textSize,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        increaseContrast: increaseContrast ?? this.increaseContrast,
        differentiateWithoutColour: differentiateWithoutColour ?? this.differentiateWithoutColour,
      );

  @override
  bool operator ==(Object other) =>
      other is Accessibility &&
      other.textSize == textSize &&
      other.reduceMotion == reduceMotion &&
      other.increaseContrast == increaseContrast &&
      other.differentiateWithoutColour == differentiateWithoutColour;

  @override
  int get hashCode => Object.hash(textSize, reduceMotion, increaseContrast, differentiateWithoutColour);
}

class Settings {
  const Settings({
    required this.themeMode,
    required this.sound,
    required this.music,
    required this.haptics,
    required this.showTimer,
    required this.reminders,
    this.reminderMinutes = 19 * 60,
    required this.cardStyle,
    required this.defaultGrid,
    required this.onboarded,
    required this.tutorialSeen,
    this.hideFinished = false,
    this.accessibility = const Accessibility(),
  });

  final ThemeMode themeMode;
  final bool sound;
  final bool music;
  final bool haptics;
  final bool showTimer;
  /// Daily reminders are on (the player turned them on and iOS allows them).
  final bool reminders;

  /// When the daily reminder fires, in minutes after local midnight.
  final int reminderMinutes;
  final CardStyle cardStyle;
  final int defaultGrid;
  final bool onboarded;
  final bool tutorialSeen;

  /// Library: leave finished packs out of every filter except Finished.
  final bool hideFinished;

  final Accessibility accessibility;

  Settings copyWith({
    ThemeMode? themeMode,
    bool? sound,
    bool? music,
    bool? haptics,
    bool? showTimer,
    bool? reminders,
    int? reminderMinutes,
    CardStyle? cardStyle,
    int? defaultGrid,
    bool? onboarded,
    bool? tutorialSeen,
    bool? hideFinished,
    Accessibility? accessibility,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        sound: sound ?? this.sound,
        music: music ?? this.music,
        haptics: haptics ?? this.haptics,
        showTimer: showTimer ?? this.showTimer,
        reminders: reminders ?? this.reminders,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        cardStyle: cardStyle ?? this.cardStyle,
        defaultGrid: defaultGrid ?? this.defaultGrid,
        onboarded: onboarded ?? this.onboarded,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
        hideFinished: hideFinished ?? this.hideFinished,
        accessibility: accessibility ?? this.accessibility,
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
      reminders: s.reminders,
      reminderMinutes: s.reminderMinutes,
      cardStyle: s.cardStyle == 'minimal' ? CardStyle.minimal : CardStyle.classic,
      defaultGrid: s.defaultGrid,
      onboarded: s.onboarded,
      tutorialSeen: s.tutorialSeen,
      hideFinished: s.getJson(_libraryKey)?['hideFinished'] == true,
      accessibility: Accessibility.fromJson(s.getJson(_accessibilityKey)),
    );
    Haptics.enabled = settings.haptics;
    Sfx.instance.soundEnabled = settings.sound;
    Sfx.instance.musicEnabled = settings.music;
    return settings;
  }

  LocalStore get _s => ref.read(localStoreProvider);

  /// Library view preferences, one JSON entry so new ones need no new store field.
  static const _libraryKey = 'libraryPrefs';

  /// Settings > Accessibility, one JSON entry.
  static const _accessibilityKey = 'accessibility';

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

  /// Stores the switch only; `RemindersController` asks iOS for permission
  /// and schedules the notifications.
  void setReminders(bool v) {
    _s.reminders = v;
    state = state.copyWith(reminders: v);
  }

  void setReminderMinutes(int v) {
    _s.reminderMinutes = v;
    state = state.copyWith(reminderMinutes: v);
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

  void setAccessibility(Accessibility v) {
    _s.setJson(_accessibilityKey, v.toJson());
    state = state.copyWith(accessibility: v);
  }

  void setHideFinished(bool v) {
    _s.setJson(_libraryKey, {...?_s.getJson(_libraryKey), 'hideFinished': v});
    state = state.copyWith(hideFinished: v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
