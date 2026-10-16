import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/haptics.dart';
import '../../core/platform.dart';
import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart' show MyPuzzle, newMyPhotoTitle;
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Upload personal photos to Appwrite Storage and play them as puzzles.
class MyPuzzlesScreen extends ConsumerStatefulWidget {
  const MyPuzzlesScreen({super.key});
  @override
  ConsumerState<MyPuzzlesScreen> createState() => _MyPuzzlesScreenState();
}

class _MyPuzzlesScreenState extends ConsumerState<MyPuzzlesScreen> {
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      showToast(context, 'No connection. Try again when you are back online.', icon: AppIcons.signal);
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 88);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(uploadRepositoryProvider).upload(userId, bytes: bytes, filename: file.name.isEmpty ? 'photo.jpg' : file.name, title: newMyPhotoTitle(DateTime.now()));
      ref.invalidate(myPuzzlesProvider);
      ref.invalidate(myPuzzleCountProvider);
      if (mounted) {
        Haptics.success();
        showToast(context, 'Photo added. Tap it to play.', icon: AppIcons.photo);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Upload failed. Check your connection and try again.', icon: AppIcons.signal);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _choose() async {
    if (!(ref.read(profileProvider).value?.isVip ?? false)) {
      final int used;
      try {
        used = await ref.read(myPuzzleCountProvider.future);
      } catch (_) {
        if (mounted) showToast(context, 'No connection. Try again when you are back online.', icon: AppIcons.signal);
        return;
      }
      if (!mounted) return;
      if (used >= Economy.freeMyPuzzles) {
        const limit = Economy.freeMyPuzzles;
        final vip = await showAppAlert(
          context,
          title: 'Photo limit reached',
          message: supportsPurchases
              ? 'You can keep $limit photos. Delete one to add another, or get VIP for unlimited photos.'
              : 'You can keep $limit photos. Delete one to add another. VIP members have no limit.',
          confirmLabel: supportsPurchases ? 'See VIP' : 'Got it',
          cancelLabel: supportsPurchases ? 'Not now' : null,
        );
        if (vip && supportsPurchases && mounted) context.push('/store?vip=1');
        return;
      }
    }
    if (!mounted) return;
    final source = await showAppActionSheet<ImageSource>(
      context,
      title: 'Add a photo',
      actions: const [AppAction('Choose from library', ImageSource.gallery), AppAction('Take a photo', ImageSource.camera)],
      cancelLabel: 'Not now',
    );
    if (source != null && mounted) _pick(source);
  }

  Future<void> _delete(MyPuzzle m) async {
    final ok = await showAppAlert(
      context,
      title: 'Delete photo?',
      message: 'The photo and its puzzle are removed from your account.',
      cancelLabel: 'Keep',
      confirmLabel: 'Delete photo',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(uploadRepositoryProvider).delete(m);
    ref.invalidate(myPuzzlesProvider);
    ref.invalidate(myPuzzleCountProvider);
  }

  /// The tile's ... button: the same Play and Delete as holding the photo.
  Future<void> _photoActions(MyPuzzle m) async {
    final action = await showAppActionSheet<String>(
      context,
      title: m.title,
      actions: const [AppAction('Play', 'play'), AppAction('Delete photo', 'delete', destructive: true)],
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      context.push('/play/${m.id}');
    } else {
      await _delete(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = ref.watch(myPuzzlesProvider);
    final progress = ref.watch(progressProvider).value ?? {};
    final isVip = ref.watch(profileProvider).value?.isVip ?? false;
    final used = ref.watch(myPuzzleCountProvider).value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('My Puzzles'),
        contentWidth: PageWidth.wide,
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: AppIcons.back, size: 38, onTap: () => context.pop())),
      ),
      body: mine.when(
        loading: () => const Loader(),
        error: (e, _) => EmptyState(icon: AppIcons.signal, title: 'Photos did not load', message: 'Check your connection and pull to refresh.'),
        data: (paged) {
          final list = paged.items;
          final side = 20 + pageInsetOf(context);
          return RefreshIndicator.adaptive(
            edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
            onRefresh: () async {
              ref.invalidate(myPuzzlesProvider);
              ref.invalidate(myPuzzleCountProvider);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                // Empty: the explanation and its one action together in the middle of the page.
                if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight, bottom: GlassTabBar.scrollEndPadding(context) - 24),
                      child: EmptyState(
                        icon: AppIcons.camera,
                        title: 'No photos yet',
                        message: 'Turn pets, trips and family into card puzzles. Only you can see your photos.',
                        action: Column(
                          children: [
                            BigButton(label: _uploading ? 'Uploading…' : 'Add photo', icon: AppIcons.plus, expand: false, loading: _uploading, onTap: _uploading ? null : _choose),
                            if (!isVip) ...[
                              const SizedBox(height: 12),
                              Text('${Economy.freeMyPuzzles} photos free · no limit with VIP', style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                // With photos: a short line, then the grid; adding a photo is the grid's first tile
                // (the Photos album idiom), so it sits where the photos go.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, MediaQuery.paddingOf(context).top + kToolbarHeight + 4, side, 0),
                    child: Text('Only you can see your photos. Tap to play, hold for more.', style: TextStyle(fontSize: TypeSize.footnote, height: 1.4, color: c.textSecondary)),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 14, side, GlassTabBar.scrollEndPadding(context)),
                  sliver: SliverGrid(
                    gridDelegate: const AdaptiveGridDelegate(childAspectRatio: 0.78),
                    delegate: SliverChildBuilderDelegate(
                      (_, index) {
                        if (index == 0) {
                          final full = !isVip && used != null && used >= Economy.freeMyPuzzles;
                          return Pressable(
                            onTap: _uploading ? null : _choose,
                            child: Container(
                              decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.lg)),
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_uploading)
                                    const CupertinoActivityIndicator()
                                  else
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle),
                                      child: Icon(AppIcons.plus, color: context.onAccent, size: 24),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(_uploading ? 'Uploading…' : 'Add photo', style: TextStyle(color: context.accent, fontWeight: FontWeight.w700, fontSize: TypeSize.callout)),
                                  if (!isVip && used != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      full ? 'All ${Economy.freeMyPuzzles} free photos used' : '${Economy.freeMyPuzzles - used.clamp(0, Economy.freeMyPuzzles)} of ${Economy.freeMyPuzzles} free left',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }
                        final i = index - 1;
                        // Next page when the grid nears its end (infinite scroll).
                        if (paged.hasMore && i >= list.length - 6) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(myPuzzlesProvider.notifier).loadMore());
                        }
                        final m = list[i];
                        final url = UploadRepository.imageUrl(m.fileId);
                        final pr = progress[m.id];
                        Widget tile({bool options = true}) => Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetImage(url: url),
                              // A visible way to the same actions, for players who never hold a tile.
                              if (options)
                                Positioned(
                                top: 2,
                                right: 2,
                                child: Semantics(
                                  button: true,
                                  label: 'Photo options',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _photoActions(m),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Glass(dark: true, radius: 15, opacity: 0.4, padding: EdgeInsets.all(6), child: Icon(AppIcons.ellipsis, color: Colors.white, size: 18)),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7, contrast: A11y.increaseContrastOf(context))),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: TypeSize.caption))),
                                      if (pr?.completed == true) Stars(count: pr!.stars, size: 12),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        // The iOS context menu: holding a photo lifts it with Play and Delete,
                        // the same gesture as in Photos.
                        return CupertinoContextMenu.builder(
                          enableHapticFeedback: true,
                          actions: [
                            CupertinoContextMenuAction(
                              trailingIcon: AppIcons.play,
                              onPressed: () {
                                Navigator.of(context, rootNavigator: true).pop();
                                context.push('/play/${m.id}');
                              },
                              child: const Text('Play'),
                            ),
                            CupertinoContextMenuAction(
                              isDestructiveAction: true,
                              trailingIcon: AppIcons.delete,
                              onPressed: () {
                                Navigator.of(context, rootNavigator: true).pop();
                                _delete(m);
                              },
                              child: const Text('Delete photo'),
                            ),
                          ],
                          builder: (ctx, animation) => animation.value < CupertinoContextMenu.animationOpensAt
                              ? GestureDetector(onTap: () => context.push('/play/${m.id}'), child: tile())
                              : AspectRatio(aspectRatio: 0.78, child: tile(options: false)),
                        );
                      },
                      childCount: list.length + 1,
                    ),
                  ),
                ),
                ],
                if (paged.hasMore)
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(bottom: 24), child: Center(child: CupertinoActivityIndicator()))),
              ],
            ),
          );
        },
      ),
    );
  }
}
