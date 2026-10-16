import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/achievements.dart';
import '../../state/profile.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

Future<void> showAvatarPicker(BuildContext context) => showAppSheet(context, builder: (_) => const AvatarPicker());

enum _Tab { all, owned, shop, rewards }

/// Avatar catalogue: four starters, a coin shop and achievement rewards.
class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({super.key});
  @override
  ConsumerState<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<AvatarPicker> {
  /// Every selectable key: plain keys for starters/shop, `family@tier` for
  /// each achievement step.
  List<String> _keysFor(_Tab tab, Set<String> owned) {
    final keys = <String>[];
    for (final a in AppIcons.avatars) {
      if (a.source == AvatarSource.achievement) {
        final req = avatarRequirement(a.key);
        final steps = req?.family.steps.length ?? 1;
        for (var i = 1; i <= steps; i++) {
          keys.add(steps == 1 ? a.key : '${a.key}@$i');
        }
      } else {
        keys.add(a.key);
      }
    }
    return switch (tab) {
      _Tab.all => keys,
      _Tab.owned => keys.where(owned.contains).toList(),
      _Tab.shop => keys.where((k) => AppIcons.avatar(k).source == AvatarSource.coins).toList(),
      _Tab.rewards => keys.where((k) => AppIcons.avatar(k).source == AvatarSource.achievement).toList(),
    };
  }

  Future<void> _tap(String key, Set<String> owned) async {
    final n = ref.read(profileProvider.notifier);
    if (owned.contains(key)) {
      await n.setIdentity(avatar: key);
      Haptics.selection();
      if (mounted) Navigator.pop(context);
      return;
    }
    final def = AppIcons.avatar(key);
    if (def.source == AvatarSource.coins) {
      final ok = await showAppAlert(
        context,
        title: 'Buy ${def.name}?',
        message: 'Yours to keep.',
        child: const Amount(currency: Currency.coins, value: Economy.avatarCoins, size: 20, fontSize: TypeSize.headline, weight: FontWeight.w700),
        cancelLabel: 'Not now',
        confirmLabel: 'Buy avatar',
      );
      if (!ok || !mounted) return;
      final bought = await n.unlockAvatar(key);
      if (!mounted) return;
      if (bought) {
        Sfx.instance.coin();
        Haptics.success();
        await n.setIdentity(avatar: key);
        if (mounted) showToast(context, '${def.name} is yours', icon: AppIcons.check);
      } else {
        showToast(context, 'Not enough coins. Visit the store or finish quests.', leading: const CoinIcon(size: 20));
        context.push('/store');
      }
      return;
    }
    final req = avatarRequirement(AppIcons.splitAvatarKey(key).family);
    final tier = AppIcons.splitAvatarKey(key).tier;
    if (req != null) {
      final f = req.family;
      final idx = (tier - 1).clamp(0, f.steps.length - 1);
      showToast(context, 'Reach "${f.title}": ${f.describe(f.steps[idx].threshold)}', icon: AppIcons.lock);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return const SizedBox(height: 200, child: Loader());
    final owned = ownedAvatarKeys(profile);
    final all = _keysFor(_Tab.all, owned);
    // Three sections instead of tabs: what the player can wear, what coins buy, what achievements give.
    final yours = all.where(owned.contains).toList();
    final shop = all.where((k) => !owned.contains(k) && AppIcons.avatar(k).source == AvatarSource.coins).toList();
    final rewards = all.where((k) => !owned.contains(k) && AppIcons.avatar(k).source == AvatarSource.achievement).toList();
    final height = MediaQuery.sizeOf(context).height * 0.78;
    const grid = SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 14, crossAxisSpacing: 8, childAspectRatio: 0.8);
    Widget header(String title, {Widget? trailing}) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Row(
              children: [
                Expanded(child: Text(title.toUpperCase(), style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary))),
                ?trailing,
              ],
            ),
          ),
        );
    Widget section(List<String> keys) => SliverGrid(
          gridDelegate: grid,
          delegate: SliverChildBuilderDelegate(
            (_, i) => _AvatarTile(avatarKey: keys[i], selected: keys[i] == profile.avatar, owned: owned.contains(keys[i]), onTap: () => _tap(keys[i], owned)),
            childCount: keys.length,
          ),
        );
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: const SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SheetHeader(title: 'Choose an avatar', subtitle: 'Tap one to wear it.'),
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      header('Yours · ${yours.length}'),
                      section(yours),
                      if (shop.isNotEmpty) ...[
                        header('Shop', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('each ', style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary, fontWeight: FontWeight.w600)),
                          const Amount(currency: Currency.coins, value: Economy.avatarCoins, size: 13, fontSize: TypeSize.caption, weight: FontWeight.w700),
                        ])),
                        section(shop),
                      ],
                      if (rewards.isNotEmpty) ...[
                        header('Achievement rewards'),
                        section(rewards),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.avatarKey, required this.selected, required this.owned, required this.onTap});
  final String avatarKey;
  final bool selected;
  final bool owned;
  final VoidCallback onTap;

  /// Full colour for what can be worn or bought; achievement rewards not earned yet are grey.
  static const _grey = ColorFilter.matrix([0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final def = AppIcons.avatar(avatarKey);
    final tier = AppIcons.splitAvatarKey(avatarKey).tier;
    final reward = def.source == AvatarSource.achievement;
    final locked = !owned && reward;
    final name = reward && tier > 1 ? '${def.name} $tier' : def.name;
    Widget avatar = AvatarCircle(avatarKey: avatarKey, size: 54);
    if (locked) avatar = Opacity(opacity: 0.55, child: ColorFiltered(colorFilter: _grey, child: avatar));
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? context.accent : Colors.transparent, width: 2.5)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (locked)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.card, border: Border.all(color: c.stroke)),
                      child: Icon(AppIcons.lock, size: 11, color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // The grid cell keeps its size: with a large text size the name shrinks to fit under the avatar.
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(name, maxLines: 1, style: TextStyle(fontSize: TypeSize.caption, color: owned ? c.textPrimary : c.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)))),
        ],
      ),
    );
  }
}
