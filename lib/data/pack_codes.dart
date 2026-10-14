import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;

/// What redeeming a pack code gave: the pack it opened, or why it did not.
class PackCodeResult {
  const PackCodeResult({required this.ok, this.packId, this.packName, this.error});
  final bool ok;
  final String? packId;
  final String? packName;

  /// `invalid`, `used`, `expired`, `signin`, `server` or `network`.
  final String? error;

  /// The calm line shown under the field when a code does not work.
  String get message => switch (error) {
        'used' => 'This code has been used as many times as it allows.',
        'expired' => 'This code has expired.',
        'signin' => 'Sign in first, then try the code again.',
        'network' => 'Could not reach the server. Check your connection and try again.',
        'server' => 'Something went wrong on our side. Try again in a moment.',
        _ => 'This code is not valid. Check it and try again.',
      };
}

/// Pack codes (function `redeem-code`): 16 characters, typed with or without dashes in any case.
class PackCodes {
  PackCodes._();

  static const length = 16;
  static final _keep = RegExp('[A-Z0-9]');

  /// The code reduced to its 16 characters (upper case, dashes and spaces dropped).
  static String normalise(String code) => code.toUpperCase().split('').where(_keep.hasMatch).join();

  /// [code] in groups of four for display: `ABCD-EFGH-JKLM-NPQR`.
  static String format(String code) {
    final n = normalise(code);
    return [for (var i = 0; i < n.length; i += 4) n.substring(i, i + 4 > n.length ? n.length : i + 4)].join('-');
  }

  /// Asks the server to open the pack of [code] for the signed-in player.
  static Future<PackCodeResult> redeem(Client client, String code) async {
    final normal = normalise(code);
    if (normal.length != length) return const PackCodeResult(ok: false, error: 'invalid');
    try {
      final exec = await Functions(client).createExecution(
        functionId: 'redeem-code',
        body: jsonEncode({'code': normal}),
        method: enums.ExecutionMethod.pOST,
        path: '/redeem',
      );
      final body = exec.responseBody.isEmpty ? <String, dynamic>{} : jsonDecode(exec.responseBody) as Map<String, dynamic>;
      return PackCodeResult(
        ok: body['ok'] == true,
        packId: body['packId']?.toString(),
        packName: body['packName']?.toString(),
        error: body['ok'] == true ? null : (body['error']?.toString() ?? 'server'),
      );
    } on AppwriteException catch (e) {
      return PackCodeResult(ok: false, error: e.code == 401 ? 'signin' : 'server');
    } catch (_) {
      return const PackCodeResult(ok: false, error: 'network');
    }
  }
}
