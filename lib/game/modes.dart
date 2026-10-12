/// Game modes decide the tiling of the picture. Each mode has its own
/// difficulty ladder and a reward multiplier (harder tilings pay more).
enum GameMode {
  cards('cards', 'Cards', 'Playing-card rectangles', 1.0),
  squares('squares', 'Squares', 'Even square tiles', 1.15),
  triangles('triangles', 'Triangles', 'Up and down triangles', 1.35),
  hexagons('hexagons', 'Hexagons', 'A honeycomb of cells', 1.5);

  const GameMode(this.code, this.label, this.description, this.multiplier);
  final String code;
  final String label;
  final String description;
  final double multiplier;

  static GameMode fromCode(String? code) => values.firstWhere((m) => m.code == code, orElse: () => GameMode.cards);
}

/// Route / storage code for a board: `cards:3x4`, `hexagons:5x7`, and with
/// the difficulty tier it was picked from, `squares:4x6t2`. The tier lets a
/// board follow the next picture's proportions (the layout is chosen per
/// picture, see `BoardSpec.forPicture`). The legacy form without a mode
/// (`3x4`) means cards.
class BoardCode {
  BoardCode._();

  static String encode(GameMode mode, int cols, int rows, {int tier = -1}) => '${mode.code}:${cols}x$rows${tier >= 0 ? 't$tier' : ''}';

  static final _grid = RegExp(r'^(\d+)(?:x(\d+))?(?:[t\-](\d+))?$');

  static ({GameMode mode, int cols, int rows, int? tier}) decode(String code) {
    var mode = GameMode.cards;
    var grid = code;
    final i = code.indexOf(':');
    if (i > 0) {
      mode = GameMode.fromCode(code.substring(0, i));
      grid = code.substring(i + 1);
    }
    final m = _grid.firstMatch(grid.trim());
    if (m == null) return (mode: mode, cols: 4, rows: 4, tier: null);
    final cols = int.tryParse(m.group(1)!) ?? 4;
    final rows = m.group(2) == null ? cols : int.tryParse(m.group(2)!) ?? cols;
    final tier = m.group(3) == null ? null : int.tryParse(m.group(3)!);
    return (mode: mode, cols: cols, rows: rows, tier: tier);
  }

  /// URL-safe variant (colon is awkward in path segments).
  static String toPath(String code) => code.replaceAll(':', '-');
  static String fromPath(String path) {
    final i = path.indexOf('-');
    return i > 0 ? '${path.substring(0, i)}:${path.substring(i + 1)}' : path;
  }
}
