/// Offensive player names (App Review guideline 1.2: user-generated content needs a filter as well
/// as Report and Block). Display names are the only text players share, so every name is checked
/// where it is chosen (the name alert, a new account's name, generated guest names) and where it is
/// shown: a name that fails shows as "Player", so names set before the filter (or by an old build)
/// are covered too.
///
/// A name is lower-cased, stripped of accents and read three ways: digits as gaps, digits as the
/// letters they look like (`$h1t`), and digits and fillers (`* . - _ '`) left out (`f4ck`, `f*ck`
/// read as `fck`). Repeated letters are collapsed (`fuuuck`) and spelled-out letters joined
/// (`f u c k`). Each word is then checked twice:
/// - [_roots] match anywhere inside a word: they never occur in ordinary words.
/// - [_words] match only a whole word (or its plural), because they hide inside innocent ones
///   (peacock, raccoon, grape, class, Sussex, canal).
class NameFilter {
  NameFilter._();

  /// What a filtered name shows as.
  static const fallback = 'Player';

  /// True when [name] contains an offensive word.
  static bool isOffensive(String name) {
    final lower = _fold(name.toLowerCase());
    if (_numbers.any(lower.contains)) return true;
    for (final word in {for (final digits in _Digits.values) ..._wordsOf(lower, digits)}) {
      for (final form in {word, _collapse(word)}) {
        if (_words.contains(form) || _words.contains(_singular(form))) return true;
        if (_roots.any(form.contains)) return true;
      }
    }
    return false;
  }

  /// [name], or [fallback] when it is offensive.
  static String shown(String name) => isOffensive(name) ? fallback : name;

  /// The words of [lower]: runs of letters, with look-alike symbols read as letters and digits read
  /// as [digits] says; single letters in a row (`f u c k`) are joined into one word.
  static List<String> _wordsOf(String lower, _Digits digits) {
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final c = String.fromCharCode(rune);
      if (digits == _Digits.drop && (_fillers.contains(c) || _digits.containsKey(c) || RegExp(r'[0-9]').hasMatch(c))) continue;
      final mapped = _symbols[c] ?? (digits == _Digits.leet ? _digits[c] : null) ?? c;
      buffer.write(RegExp(r'[a-z]').hasMatch(mapped) ? mapped : ' ');
    }
    final parts = buffer.toString().split(' ').where((w) => w.isNotEmpty).toList();
    final words = <String>[];
    final spelled = StringBuffer();
    void flush() {
      if (spelled.length > 1) words.add(spelled.toString());
      spelled.clear();
    }

    for (final p in parts) {
      if (p.length == 1) {
        spelled.write(p);
      } else {
        flush();
        words.add(p);
      }
    }
    flush();
    return words;
  }

  static String _singular(String word) => word.length > 4 && word.endsWith('es')
      ? word.substring(0, word.length - 2)
      : word.length > 3 && word.endsWith('s') ? word.substring(0, word.length - 1) : word;

  static String _collapse(String word) => word.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

  static String _fold(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      final c = String.fromCharCode(rune);
      out.write(_accents[c] ?? c);
    }
    return out.toString();
  }

  static const _symbols = {'@': 'a', r'$': 's', '!': 'i', '|': 'i', '+': 't', '€': 'e'};
  static const _fillers = {'*', '.', '-', '_', "'"};
  static const _digits = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '9': 'g'};
  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'č': 'c', 'ç': 'c', 'ć': 'c', 'ď': 'd',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ě': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ľ': 'l',
    'ĺ': 'l', 'ł': 'l', 'ň': 'n', 'ñ': 'n', 'ń': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ø': 'o', 'ŕ': 'r', 'ř': 'r', 'š': 's', 'ś': 's', 'ß': 'ss', 'ť': 't', 'ú': 'u', 'ù': 'u', 'û': 'u',
    'ü': 'u', 'ů': 'u', 'ý': 'y', 'ÿ': 'y', 'ž': 'z', 'ź': 'z', 'ż': 'z',
  };

  /// Hate symbols written as numbers.
  static const _numbers = ['1488', '14/88', '14 88'];

  /// Offensive anywhere inside a word. Only roots that no ordinary word contains (so not "rapist",
  /// which is in "therapist", or "pica", which is in "Picasso" and "tropical").
  static const _roots = {
    // English
    'fuck', 'fck', 'fvck', 'phuck', 'shit', 'cunt', 'nigg', 'faggot', 'whore', 'slut', 'bitch', 'bastard', 'asshole',
    'arsehole', 'dickhead', 'motherf', 'cocksuck', 'penis', 'vagina', 'dildo', 'porn', 'hitler',
    'retard', 'wanker', 'twat', 'jizz', 'blowjob', 'handjob', 'orgasm', 'pedophil', 'paedophil',
    'pedofil', 'molest', 'wetback', 'raghead', 'towelhead', 'kkk',
    // Slovak and Czech
    'kurva', 'kurvy', 'jebem', 'jebat', 'jebn', 'hovno', 'sracka', 'zmrd', 'kokot', 'skurvy',
    'chuj', 'buzerant',
    // German, Dutch, Polish
    'scheiss', 'fotze', 'hurensohn', 'wichser', 'arschloch', 'kurwa', 'pierdol', 'jebac', 'kanker',
    // Spanish, Portuguese, Italian, French
    'mierda', 'cabron', 'pendejo', 'maricon', 'caralho', 'buceta', 'cazzo', 'stronzo', 'vaffanculo',
    'puttana', 'putain', 'salope', 'connard', 'encule',
  };

  /// Offensive as a whole word only (plurals included).
  static const _words = {
    // English
    'ass', 'arse', 'cock', 'dick', 'pussy', 'tits', 'titty', 'boob', 'cum', 'sex', 'sexy', 'anal',
    'anus', 'rape', 'raped', 'raping', 'rapist', 'nazi', 'heil', 'fag', 'dyke', 'tranny', 'homo',
    'coon', 'chink', 'gook', 'kike', 'spic', 'paki', 'spaz', 'crap', 'piss', 'pissed', 'xxx', 'milf',
    'horny', 'nude', 'boner', 'hoe', 'skank', 'prick', 'bollocks', 'incest', 'pedo', 'paedo', 'fuk',
    'niga', 'wank', 'idiot',
    // Slovak and Czech
    'pica', 'pice', 'picus', 'debil', 'cigan', 'kreten',
    // Spanish, Portuguese, Italian, French, Dutch
    'puta', 'puto', 'porra', 'pute', 'merde', 'batard', 'kut', 'culo', 'coglione',
  };
}

/// How a name's digits are read: as gaps between words, as the letters they look like, or left out.
enum _Digits { split, leet, drop }
