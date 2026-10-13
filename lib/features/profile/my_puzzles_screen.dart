import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../state/auth.dart';
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
      await ref.read(uploadRepositoryProvider).upload(userId, bytes: bytes, filename: file.name.isEmpty ? 'photo.jpg' : file.name, title: 'My photo ${DateTime.now().day}/${DateTime.now().month}');
      ref.invalidate(myPuzzlesProvider);
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

  void _choose() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add a photo'),
        actions: [
          CupertinoActionSheetAction(onPressed: () { Navigator.pop(ctx); _pick(ImageSource.gallery); }, child: const Text('Choose from library')),
          CupertinoActionSheetAction(onPressed: () { Navigator.pop(ctx); _pick(ImageSource.camera); }, child: const Text('Take a photo')),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = ref.watch(myPuzzlesProvider);
    final progress = ref.watch(progressProvider).value ?? {};
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('My Puzzles'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.back, size: 38, onTap: () => context.pop())),
      ),
      body: mine.when(
        loading: () => const Loader(),
        error: (e, _) => EmptyState(icon: AppIcons.signal, title: 'Photos did not load', message: 'Check your connection and pull to refresh.'),
        data: (paged) {
          final list = paged.items;
          return RefreshIndicator.adaptive(
            edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
            onRefresh: () async => ref.invalidate(myPuzzlesProvider),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 20, 0),
                    child: BigButton(label: _uploading ? 'Uploading…' : 'Add photo', icon: CupertinoIcons.plus, loading: _uploading, onTap: _uploading ? null : _choose),
                  ),
                ),
                if (list.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: AppIcons.camera, title: 'No photos yet', message: 'Turn pets, trips and family into card puzzles. Photos stay private to your account.'))
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, GlassTabBar.scrollEndPadding(context)),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          // Next page when the grid nears its end (infinite scroll).
                          if (paged.hasMore && i >= list.length - 6) {
                            WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(myPuzzlesProvider.notifier).loadMore());
                          }
                          final m = list[i];
                          final url = UploadRepository.imageUrl(m.fileId);
                          final pr = progress[m.id];
                          return Pressable(
                            onTap: () => context.push('/play/${m.id}'),
                            onLongPress: () async {
                              final ok = await showAppAlert(
                                context,
                                title: 'Delete photo?',
                                message: 'The photo and its puzzle are removed from your account.',
                                cancelLabel: 'Keep',
                                confirmLabel: 'Delete photo',
                                destructive: true,
                              );
                              if (ok) {
                                await ref.read(uploadRepositoryProvider).delete(m);
                                ref.invalidate(myPuzzlesProvider);
                              }
                            },
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  NetImage(url: url),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7)),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
                                          if (pr?.completed == true) Stars(count: pr!.stars, size: 12),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: list.length,
                      ),
                    ),
                  ),
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
