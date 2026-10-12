import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts/chart_card.dart';
import 'add_photo.dart';
import 'photo_image.dart';

/// Progress tab card: the latest photos and a count, or an invitation to add
/// the first one.
class PhotosCard extends ConsumerStatefulWidget {
  const PhotosCard({super.key});

  @override
  ConsumerState<PhotosCard> createState() => _PhotosCardState();
}

class _PhotosCardState extends ConsumerState<PhotosCard> {
  static const _shown = 4;

  @override
  void initState() {
    super.initState();
    unawaited(_recoverLost());
  }

  /// A photo taken just before Android killed the app is offered again.
  Future<void> _recoverLost() async {
    final lost = await ref.read(photoPickerProvider).lost();
    if (lost != null && mounted) await filePhoto(context, ref, lost);
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider).value;
    if (photos == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;

    if (photos.isEmpty) {
      return ChartCard(
        title: 'Photos',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'See how you change. Add a photo now and compare it with later '
              'ones.',
              style: t.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => addPhoto(context, ref),
                icon: const AppIcon(AppIcons.camera, size: IconSizes.sm),
                label: const Text('Add photo'),
              ),
            ),
          ],
        ),
      );
    }

    final latest = photos.first;
    final count = '${photos.length} photo${photos.length == 1 ? '' : 's'}';
    return ChartCard(
      title: 'Photos',
      onTap: () => context.go('/progress/photos'),
      trailing: TextButton(
        onPressed: () => addPhoto(context, ref),
        child: const Text('Add'),
      ),
      caption: '$count · latest ${photoDay.format(latest.takenAt)}',
      child: Row(
        spacing: Space.sm,
        children: [
          for (var i = 0; i < _shown; i++)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: i < photos.length
                    ? ClipRRect(
                        borderRadius: Radii.smAll,
                        child: PhotoImage(photos[i], width: 120),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
