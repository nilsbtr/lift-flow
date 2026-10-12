import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/photos.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'add_photo.dart';
import 'photo_image.dart';

final _month = DateFormat('MMMM y');
final _dayMonth = DateFormat('d MMM');

/// Progress photos by month, newest first. Reached from the Progress tab.
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_sweep());
  }

  /// Removes image files left behind by an interrupted delete.
  Future<void> _sweep() async {
    try {
      await ref.read(photoServiceProvider).sweep();
    } catch (_) {
      // Housekeeping only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider).value;
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        actions: [
          if ((photos?.length ?? 0) >= 2)
            TextButton(
              onPressed: () => context.go('/progress/photos/compare'),
              child: const Text('Compare'),
            ),
          IconButton(
            tooltip: 'Add photo',
            icon: const AppIcon(AppIcons.plus),
            onPressed: () => addPhoto(context, ref),
          ),
        ],
      ),
      body: photos == null
          ? const SizedBox.shrink()
          : photos.isEmpty
          ? EmptyState(
              icon: AppIcons.camera,
              title: 'No photos yet',
              message: 'Add a photo every few weeks to see how you change.',
              action: FilledButton.icon(
                onPressed: () => addPhoto(context, ref),
                icon: const AppIcon(AppIcons.camera, size: IconSizes.sm),
                label: const Text('Add photo'),
              ),
            )
          : CustomScrollView(
              slivers: [
                for (final m in groupByMonth(photos)) ...[
                  SliverToBoxAdapter(
                    child: SectionLabel(
                      _month.format(m.month),
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: Text(
                          '${m.photos.length}',
                          style: t.labelMedium?.copyWith(color: muted),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 120,
                            mainAxisSpacing: Space.sm,
                            crossAxisSpacing: Space.sm,
                          ),
                      itemCount: m.photos.length,
                      itemBuilder: (_, i) => _Thumb(m.photos[i]),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Text(
                      'Photos stay on this device. The regular backup leaves '
                      'them out: export them in Settings.',
                      style: t.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.photo);
  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Photo from ${photoDay.format(photo.takenAt)}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: Radii.smAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(photo, width: 160),
            Positioned(
              left: Space.xs,
              bottom: Space.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.xs + 2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.85),
                  borderRadius: Radii.pill,
                ),
                child: Text(
                  _dayMonth.format(photo.takenAt),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurface),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => context.push('/progress/photos/${photo.id}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
