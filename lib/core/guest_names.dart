import 'package:unique_names_generator/unique_names_generator.dart';

/// Friendly random display names for new guests, e.g. "Brave Otter".
class GuestNames {
  GuestNames._();
  static final _generator = UniqueNamesGenerator(
    config: Config(length: 2, separator: ' ', style: Style.capital, dictionaries: [adjectives, animals]),
  );

  static String next() {
    final name = _generator.generate();
    return name.length > 20 ? name.substring(0, 20) : name;
  }
}
