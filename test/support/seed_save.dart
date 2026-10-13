import 'dart:convert';

/// SharedPreferences values holding a save on the device for the player without an account
/// (`local`), the way the save sync stores it: widget tests start from it and then use the real
/// profile and progress notifiers, offline.
Map<String, Object> seededSave({Map<String, dynamic> profile = const {}, Map<String, Map<String, dynamic>> progress = const {}}) => {
      'sync.v1.local.rows': jsonEncode({
        'profile': {'userId': 'local', 'coins': 500, 'tickets': 3, 'hints': 3, ...profile},
        'progress': {for (final e in progress.entries) e.key: {'userId': 'local', 'puzzleId': e.key, ...e.value}},
        'synced': true,
      }),
    };
