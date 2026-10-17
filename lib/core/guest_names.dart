import 'package:unique_names_generator/unique_names_generator.dart';

import 'name_filter.dart';

/// Friendly random display names for new guests, e.g. "Brave Otter".
class GuestNames {
  GuestNames._();
  static final _generator = UniqueNamesGenerator(
    config: Config(length: 2, separator: ' ', style: Style.capital, dictionaries: [adjectives, animals]),
  );

  /// Names fit in 20 characters. A longer pair is drawn again rather than cut: cutting
  /// "Straightforward Cockroach" left a rude word, so a draw must also pass [NameFilter].
  static String next() {
    while (true) {
      final name = _generator.generate();
      if (name.length <= 20 && !NameFilter.isOffensive(name)) return name;
    }
  }
}
