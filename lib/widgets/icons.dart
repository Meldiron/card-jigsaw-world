import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../models/models.dart';

enum AvatarSource { free, coins, achievement }

/// One avatar in the catalogue.
class AvatarDef {
  const AvatarDef(this.key, this.name, this.icon, this.color, this.source, {this.achievementId});
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final AvatarSource source;
  /// Achievement family that grants this avatar (tier n = step n).
  final String? achievementId;
}

/// Semantic icon system. Every pictogram in the app comes from here so the
/// visual language stays consistent: drawn currency marks (coin, ticket,
/// hint) and Material Symbols for everything else.
class AppIcons {
  AppIcons._();

  // Navigation / sections
  static const home = CupertinoIcons.house_fill;
  static const library = CupertinoIcons.square_grid_2x2_fill;
  static const events = Icons.redeem_rounded;
  /// Quests tab (daily and weekly quests plus live events).
  static const quests = CupertinoIcons.flag_fill;
  static const questsOutline = CupertinoIcons.flag;
  static const social = CupertinoIcons.person_2_fill;
  static const profile = CupertinoIcons.person_crop_circle_fill;

  // Meta features
  static const dailyGift = Icons.redeem_rounded;
  static const wheel = Icons.donut_large_rounded;
  static const piggy = Icons.savings_rounded;
  static const dailyPuzzle = Icons.today_rounded;
  static const streak = Icons.local_fire_department_rounded;
  static const xp = Icons.auto_awesome_rounded;
  static const star = CupertinoIcons.star_fill;
  static const starOutline = CupertinoIcons.star;
  static const trophy = Icons.emoji_events_rounded;
  static const crown = Icons.workspace_premium_rounded;
  static const vip = Icons.workspace_premium_rounded;
  static const lock = CupertinoIcons.lock_fill;
  static const unlock = CupertinoIcons.lock_open_fill;
  static const check = CupertinoIcons.checkmark_seal_fill;
  static const photo = CupertinoIcons.photo_on_rectangle;
  static const camera = CupertinoIcons.camera_fill;
  static const credit = CupertinoIcons.camera;
  static const community = Icons.public_rounded;
  static const friends = CupertinoIcons.person_2_fill;
  static const addFriend = CupertinoIcons.person_add_solid;
  static const copy = CupertinoIcons.doc_on_doc;
  static const video = Icons.play_circle_fill_rounded;
  static const bundle = Icons.card_giftcard_rounded;
  static const puzzle = Icons.extension_rounded;
  static const bigBoard = Icons.grid_on_rounded;
  static const level = Icons.military_tech_rounded;
  static const swaps = CupertinoIcons.arrow_right_arrow_left;
  static const time = CupertinoIcons.time;
  static const save = CupertinoIcons.cloud_upload_fill;
  static const signal = CupertinoIcons.antenna_radiowaves_left_right;
  static const wave = Icons.waving_hand_rounded;
  static const sparkle = CupertinoIcons.sparkles;
  static const balloon = Icons.celebration_rounded;
  static const image = CupertinoIcons.photo;
  static const mail = CupertinoIcons.envelope_fill;
  static const receipt = CupertinoIcons.doc_plaintext;

  // Boosters
  static const undo = Icons.undo_rounded;
  static const peek = Icons.visibility_rounded;
  static const hint = Icons.lightbulb_rounded;
  static const magic = Icons.auto_fix_high_rounded;

  /// Icon for a pack category.
  static IconData category(String category) => switch (category.toLowerCase()) {
        'nature' => Icons.landscape_rounded,
        'animals' => Icons.pets_rounded,
        'food' => Icons.local_cafe_rounded,
        'travel' => Icons.location_city_rounded,
        'premium' => Icons.ac_unit_rounded,
        'art' => Icons.palette_rounded,
        'space' => Icons.rocket_launch_rounded,
        'seasonal' => Icons.eco_rounded,
        'daily' => Icons.calendar_month_rounded,
        _ => Icons.extension_rounded,
      };

  /// Icon for a board tier (index into GridSpec.tiers).
  static IconData tier(int index) => const [
        Icons.spa_rounded,
        Icons.eco_rounded,
        Icons.coffee_rounded,
        Icons.extension_rounded,
        Icons.local_fire_department_rounded,
        Icons.diamond_rounded,
        Icons.emoji_events_rounded,
        Icons.workspace_premium_rounded,
      ][index.clamp(0, 7)];

  static IconData eventType(EventType t) => switch (t) {
        EventType.seasonal => Icons.eco_rounded,
        EventType.social => Icons.public_rounded,
        EventType.weekly => Icons.bolt_rounded,
        EventType.daily => Icons.today_rounded,
      };

  /// Avatar catalogue. Keys are stored on the profile; a tiered avatar is
  /// stored as `family@tier` (e.g. `solver@3`).
  static const avatars = <AvatarDef>[
    // Free starters
    AvatarDef('fox', 'Fox', Icons.pets_rounded, Color(0xFFB45309), AvatarSource.free),
    AvatarDef('leaf', 'Leaf', Icons.eco_rounded, Color(0xFF15803D), AvatarSource.free),
    AvatarDef('drop', 'Drop', Icons.water_drop_rounded, Color(0xFF1D4ED8), AvatarSource.free),
    AvatarDef('star', 'Star', Icons.star_rounded, Color(0xFF4338CA), AvatarSource.free),
    // Shop
    AvatarDef('bolt', 'Bolt', Icons.bolt_rounded, Color(0xFF92400E), AvatarSource.coins),
    AvatarDef('heart', 'Heart', Icons.favorite_rounded, Color(0xFFBE123C), AvatarSource.coins),
    AvatarDef('flower', 'Flower', Icons.local_florist_rounded, Color(0xFFA21CAF), AvatarSource.coins),
    AvatarDef('sun', 'Sun', Icons.wb_sunny_rounded, Color(0xFFC2410C), AvatarSource.coins),
    AvatarDef('moon', 'Moon', Icons.nightlight_round, Color(0xFF3730A3), AvatarSource.coins),
    AvatarDef('rocket', 'Rocket', Icons.rocket_launch_rounded, Color(0xFF334155), AvatarSource.coins),
    AvatarDef('music', 'Note', Icons.music_note_rounded, Color(0xFF0F766E), AvatarSource.coins),
    AvatarDef('game', 'Controller', Icons.sports_esports_rounded, Color(0xFF6D28D9), AvatarSource.coins),
    AvatarDef('camera', 'Camera', Icons.photo_camera_rounded, Color(0xFF0369A1), AvatarSource.coins),
    AvatarDef('palette', 'Palette', Icons.palette_rounded, Color(0xFF9F1239), AvatarSource.coins),
    AvatarDef('diamond', 'Diamond', Icons.diamond_rounded, Color(0xFF0E7490), AvatarSource.coins),
    AvatarDef('sparkle', 'Sparkle', Icons.auto_awesome_rounded, Color(0xFF7E22CE), AvatarSource.coins),
    AvatarDef('anchor', 'Anchor', Icons.anchor_rounded, Color(0xFF1E3A8A), AvatarSource.coins),
    AvatarDef('cat', 'Cat', Icons.cruelty_free_rounded, Color(0xFF78350F), AvatarSource.coins),
    AvatarDef('mountain', 'Mountain', Icons.landscape_rounded, Color(0xFF365314), AvatarSource.coins),
    AvatarDef('wave', 'Wave', Icons.waves_rounded, Color(0xFF155E75), AvatarSource.coins),
    AvatarDef('coffee', 'Coffee', Icons.coffee_rounded, Color(0xFF713F12), AvatarSource.coins),
    AvatarDef('book', 'Book', Icons.menu_book_rounded, Color(0xFF3F3F46), AvatarSource.coins),
    AvatarDef('bike', 'Bicycle', Icons.pedal_bike_rounded, Color(0xFF115E59), AvatarSource.coins),
    AvatarDef('plane', 'Plane', Icons.flight_rounded, Color(0xFF1E40AF), AvatarSource.coins),
    AvatarDef('umbrella', 'Umbrella', Icons.beach_access_rounded, Color(0xFF9D174D), AvatarSource.coins),
    AvatarDef('snow', 'Snowflake', Icons.ac_unit_rounded, Color(0xFF0C4A6E), AvatarSource.coins),
    AvatarDef('pizza', 'Pizza', Icons.local_pizza_rounded, Color(0xFFB91C1C), AvatarSource.coins),
    AvatarDef('cake', 'Cake', Icons.cake_rounded, Color(0xFFBE185D), AvatarSource.coins),
    AvatarDef('globe', 'Globe', Icons.public_rounded, Color(0xFF166534), AvatarSource.coins),
    AvatarDef('key', 'Key', Icons.key_rounded, Color(0xFF854D0E), AvatarSource.coins),
    AvatarDef('ghost', 'Ghost', Icons.blur_on_rounded, Color(0xFF475569), AvatarSource.coins),
    AvatarDef('bug', 'Ladybird', Icons.bug_report_rounded, Color(0xFF991B1B), AvatarSource.coins),
    // Achievement rewards (tiered families share a key; tier is appended as @n)
    AvatarDef('solver', 'Solver', Icons.extension_rounded, Color(0xFF4338CA), AvatarSource.achievement, achievementId: 'solver'),
    AvatarDef('perfect', 'Perfectionist', Icons.star_rounded, Color(0xFFB45309), AvatarSource.achievement, achievementId: 'perfect'),
    AvatarDef('flame', 'Streak', Icons.local_fire_department_rounded, Color(0xFFC2410C), AvatarSource.achievement, achievementId: 'streak'),
    AvatarDef('medal', 'Veteran', Icons.military_tech_rounded, Color(0xFF6D28D9), AvatarSource.achievement, achievementId: 'level'),
    AvatarDef('cards', 'Card Sharp', Icons.style_rounded, Color(0xFF0F766E), AvatarSource.achievement, achievementId: 'cards'),
    AvatarDef('square', 'Square Deal', Icons.grid_view_rounded, Color(0xFF1D4ED8), AvatarSource.achievement, achievementId: 'squares'),
    AvatarDef('triangle', 'Triangulate', Icons.change_history_rounded, Color(0xFF9F1239), AvatarSource.achievement, achievementId: 'triangles'),
    AvatarDef('hex', 'Honeycomb', Icons.hexagon_rounded, Color(0xFF92400E), AvatarSource.achievement, achievementId: 'hexagons'),
    AvatarDef('grid', 'Big Boards', Icons.grid_on_rounded, Color(0xFF334155), AvatarSource.achievement, achievementId: 'big'),
    AvatarDef('crown', 'Master', Icons.workspace_premium_rounded, Color(0xFF854D0E), AvatarSource.achievement, achievementId: 'master'),
    AvatarDef('mind', 'No Hints', Icons.psychology_rounded, Color(0xFF3730A3), AvatarSource.achievement, achievementId: 'nohints'),
    AvatarDef('album', 'Collector', Icons.collections_bookmark_rounded, Color(0xFF0369A1), AvatarSource.achievement, achievementId: 'collector'),
    AvatarDef('calendar', 'Daily Devotee', Icons.today_rounded, Color(0xFF15803D), AvatarSource.achievement, achievementId: 'daily'),
    AvatarDef('ticket', 'Event Goer', Icons.confirmation_number_rounded, Color(0xFFBE123C), AvatarSource.achievement, achievementId: 'events'),
    AvatarDef('owl', 'Night Owl', Icons.dark_mode_rounded, Color(0xFF1E293B), AvatarSource.achievement, achievementId: 'nightowl'),
    AvatarDef('bird', 'Early Bird', Icons.wb_twilight_rounded, Color(0xFFC2410C), AvatarSource.achievement, achievementId: 'earlybird'),
    AvatarDef('speed', 'Quick Hands', Icons.speed_rounded, Color(0xFF0E7490), AvatarSource.achievement, achievementId: 'speed'),
    AvatarDef('marathon', 'Marathon', Icons.directions_run_rounded, Color(0xFF065F46), AvatarSource.achievement, achievementId: 'marathon'),
    AvatarDef('shapes', 'All Modes', Icons.category_rounded, Color(0xFF7E22CE), AvatarSource.achievement, achievementId: 'allmodes'),
    AvatarDef('stars', 'Star Hoarder', Icons.stars_rounded, Color(0xFFA16207), AvatarSource.achievement, achievementId: 'starhoarder'),
    AvatarDef('vault', 'Rich', Icons.savings_rounded, Color(0xFF166534), AvatarSource.achievement, achievementId: 'rich'),
    AvatarDef('vip', 'VIP', Icons.workspace_premium_rounded, Color(0xFF111827), AvatarSource.achievement, achievementId: 'vip'),
    AvatarDef('friends', 'Social', Icons.people_alt_rounded, Color(0xFF155E75), AvatarSource.achievement, achievementId: 'social'),
  ];

  static const freeAvatarKeys = ['fox', 'leaf', 'drop', 'star'];

  /// Splits `family@tier` into its parts; plain keys are tier 1.
  static ({String family, int tier}) splitAvatarKey(String? key) {
    if (key == null || key.isEmpty) return (family: 'fox', tier: 1);
    final i = key.indexOf('@');
    if (i < 0) return (family: key, tier: 1);
    return (family: key.substring(0, i), tier: int.tryParse(key.substring(i + 1)) ?? 1);
  }

  static AvatarDef avatar(String? key) {
    final family = splitAvatarKey(key).family;
    return avatars.firstWhere((a) => a.key == family, orElse: () => avatars.first);
  }
}

enum Currency { coins, tickets, hints }

/// Round gold coin with an embossed star – the app's coin mark.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE09E00));
    canvas.drawCircle(
      c.translate(0, -r * 0.06),
      r * 0.92,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFE08A), Color(0xFFFFC53D)]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r * 0.68, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.12)
      ..color = const Color(0xFFE09E00).withValues(alpha: 0.85));
    final path = Path();
    const n = 5;
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final rad = i.isEven ? r * 0.42 : r * 0.19;
      final p = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFB97800));
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

/// Teal admission ticket with notched sides.
class TicketIcon extends StatelessWidget {
  const TicketIcon({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size * 1.25, size), painter: _TicketPainter());
}

class _TicketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * 0.14, w, h * 0.72), Radius.circular(h * 0.16));
    final notch = h * 0.16;
    final body = Path()..addRRect(rect);
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, h / 2), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(w, h / 2), radius: notch));
    final shape = Path.combine(PathOperation.difference, body, holes);
    canvas.drawPath(
      shape,
      Paint()..shader = const LinearGradient(colors: [Color(0xFF34D3C4), Color(0xFF1E9E93)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & size),
    );
    // Perforation line
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = math.max(1, h * 0.08);
    final x = w * 0.66;
    for (var y = h * 0.24; y < h * 0.82; y += h * 0.16) {
      canvas.drawLine(Offset(x, y), Offset(x, y + h * 0.08), dash);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.36, w * 0.36, h * 0.1), Radius.circular(h * 0.05)), Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.54, w * 0.26, h * 0.1), Radius.circular(h * 0.05)), Paint()..color = Colors.white.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

/// Amber bulb mark for hints.
class HintIcon extends StatelessWidget {
  const HintIcon({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Brand.hint),
        child: Icon(Icons.lightbulb_rounded, size: size * 0.62, color: Colors.white),
      );
}

Widget currencyIcon(Currency c, {double size = 18}) => switch (c) {
      Currency.coins => CoinIcon(size: size),
      Currency.tickets => TicketIcon(size: size),
      Currency.hints => HintIcon(size: size),
    };

/// Inline "icon + number" used for prices, rewards and balances.
class Amount extends StatelessWidget {
  const Amount({
    super.key,
    required this.currency,
    required this.value,
    this.size = 16,
    this.fontSize,
    this.color,
    this.prefix = '',
    this.suffix = '',
    this.weight = FontWeight.w900,
  });
  final Currency currency;
  final Object value;
  final double size;
  final double? fontSize;
  final Color? color;
  final String prefix;
  final String suffix;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        currencyIcon(currency, size: size),
        SizedBox(width: size * 0.3),
        Text('$prefix$value$suffix', style: TextStyle(fontWeight: weight, fontSize: fontSize ?? size * 0.95, color: color ?? context.colors.textPrimary)),
      ],
    );
  }
}

/// Rounded-square icon tile used by quick actions, boosters and list rows.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 40, this.gradient, this.color, this.iconColor = Colors.white, this.radius = 12, this.child});
  final IconData icon;
  final double size;
  final Gradient? gradient;
  final Color? color;
  final Color iconColor;
  final double radius;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: gradient, color: gradient == null ? (color ?? context.colors.accentTint) : null, borderRadius: BorderRadius.circular(radius)),
        child: child ?? Icon(icon, size: size * 0.52, color: gradient == null && color == null ? context.accent : iconColor),
      );
}

/// Circular avatar drawn from the profile's avatar key. Tiered avatars
/// (`family@n`) earn a frame that grows with the tier.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.avatarKey, this.size = 40, this.border = false, this.tier});
  final String? avatarKey;
  final double size;
  final bool border;
  /// Overrides the tier parsed from [avatarKey].
  final int? tier;

  @override
  Widget build(BuildContext context) {
    final parts = AppIcons.splitAvatarKey(avatarKey);
    final a = AppIcons.avatar(parts.family);
    final t = tier ?? parts.tier;
    final ring = switch (t) { <= 1 => 0.0, 2 => size * 0.06, _ => size * 0.08 };
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: a.color,
        border: border && t <= 1 ? Border.all(color: context.colors.card, width: 3) : null,
      ),
      child: Container(
        width: size * 0.78,
        height: size * 0.78,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t >= 2 ? Color.lerp(a.color, Colors.black, 0.22) : a.color),
        child: Icon(a.icon, size: size * 0.5, color: Colors.white),
      ),
    );
    if (t <= 1) return disc;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _TierRingPainter(tier: t, ring: ring, card: context.colors.card)),
          Padding(padding: EdgeInsets.all(ring + (t >= 4 ? size * 0.05 : size * 0.02)), child: FittedBox(child: disc)),
          if (t >= 4)
            Positioned(
              right: -size * 0.02,
              bottom: -size * 0.02,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.coin, border: Border.all(color: context.colors.card, width: math.max(1, size * 0.04))),
                child: Icon(Icons.star_rounded, size: size * 0.2, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _TierRingPainter extends CustomPainter {
  _TierRingPainter({required this.tier, required this.ring, required this.card});
  final int tier;
  final double ring;
  final Color card;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - ring / 2;
    final color = tier == 2 ? const Color(0xFFA3A8B5) : Brand.coin;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = ring..color = color);
    if (tier >= 3) {
      // Notch marks on the gold ring.
      final notch = Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(1.2, ring * 0.35)..color = card.withValues(alpha: 0.9)..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(Offset(c.dx + math.cos(a) * (r - ring * 0.35), c.dy + math.sin(a) * (r - ring * 0.35)), Offset(c.dx + math.cos(a) * (r + ring * 0.35), c.dy + math.sin(a) * (r + ring * 0.35)), notch);
      }
    }
    if (tier >= 4) {
      canvas.drawCircle(c, r - ring * 1.6, Paint()..style = PaintingStyle.stroke..strokeWidth = ring * 0.5..color = color);
    }
  }

  @override
  bool shouldRepaint(_TierRingPainter o) => o.tier != tier || o.ring != ring || o.card != card;
}
