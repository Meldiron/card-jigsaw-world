import 'package:flutter/cupertino.dart';
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
  _Tab _tab = _Tab.all;

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
        child: const Amount(currency: Currency.coins, value: Economy.avatarCoins, size: 20, fontSize: 17, weight: FontWeight.w700),
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
    final keys = _keysFor(_tab, owned);
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                Text('Choose an avatar', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('${owned.length} owned · tap to wear, buy or see how to earn', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<_Tab>(
                    groupValue: _tab,
                    backgroundColor: c.boardBackground,
                    thumbColor: c.card,
                    children: const {
                      _Tab.all: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('All', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      _Tab.owned: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Owned', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      _Tab.shop: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Shop', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      _Tab.rewards: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Rewards', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    },
                    onValueChanged: (v) => setState(() => _tab = v ?? _Tab.all),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: keys.isEmpty
                ? const EmptyState(icon: AppIcons.lock, title: 'Nothing here yet', message: 'Finish achievements or visit the shop to add avatars.')
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.74),
                    itemCount: keys.length,
                    itemBuilder: (_, i) => _AvatarTile(avatarKey: keys[i], selected: keys[i] == profile.avatar, owned: owned.contains(keys[i]), onTap: () => _tap(keys[i], owned)),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final def = AppIcons.avatar(avatarKey);
    final tier = AppIcons.splitAvatarKey(avatarKey).tier;
    final Widget caption = switch (def.source) {
      AvatarSource.free => Text(def.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
      AvatarSource.coins => owned ? Text(def.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)) : const Amount(currency: Currency.coins, value: Economy.avatarCoins, size: 12, fontSize: 11, weight: FontWeight.w600),
      AvatarSource.achievement => Text(owned ? def.name : (tier > 1 ? 'Tier $tier' : 'Reward'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
    };
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
                Opacity(opacity: owned ? 1 : 0.45, child: AvatarCircle(avatarKey: avatarKey, size: 52)),
                if (!owned)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.card, border: Border.all(color: c.stroke)),
                      child: Icon(def.source == AvatarSource.coins ? CupertinoIcons.bag_fill : AppIcons.lock, size: 11, color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          caption,
        ],
      ),
    );
  }
}
