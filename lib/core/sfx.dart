import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Sound effects + music. Files live in assets/sfx and are tiny generated WAVs.
class Sfx {
  Sfx._();
  static final Sfx instance = Sfx._();

  bool soundEnabled = true;
  bool musicEnabled = true;

  final _pool = <AudioPlayer>[];
  int _next = 0;
  AudioPlayer? _music;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {AVAudioSessionOptions.mixWithOthers}),
        android: const AudioContextAndroid(isSpeakerphoneOn: false, stayAwake: false, contentType: AndroidContentType.sonification, usageType: AndroidUsageType.game, audioFocus: AndroidAudioFocus.none),
      ));
      for (var i = 0; i < 4; i++) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _pool.add(p);
      }
    } catch (e) {
      debugPrint('Sfx init failed: $e');
    }
  }

  Future<void> _play(String name, {double volume = 1}) async {
    if (!soundEnabled || _pool.isEmpty) return;
    try {
      final p = _pool[_next++ % _pool.length];
      await p.stop();
      await p.play(AssetSource('sfx/$name.wav'), volume: volume);
    } catch (e) {
      debugPrint('Sfx play failed: $e');
    }
  }

  void tap() => _play('tap', volume: 0.6);
  void pick() => _play('pick', volume: 0.7);
  void swap() => _play('swap', volume: 0.8);
  void lock() => _play('lock');
  void snap() => _play('snap', volume: 0.8);
  void win() => _play('win');
  void coin() => _play('coin', volume: 0.9);
  void whoosh() => _play('whoosh', volume: 0.7);
  void error() => _play('error', volume: 0.6);
  void spin() => _play('spin', volume: 0.8);

  Future<void> startMusic() async {
    if (!musicEnabled) return;
    try {
      _music ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      if (_music!.state == PlayerState.playing) return;
      await _music!.play(AssetSource('sfx/music.wav'), volume: 0.35);
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  Future<void> stopMusic() async {
    try { await _music?.stop(); } catch (_) {}
  }

  void setMusic(bool on) {
    musicEnabled = on;
    if (on) { startMusic(); } else { stopMusic(); }
  }
}
