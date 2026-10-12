import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/photos.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'photo_image.dart';

/// Two photos side by side with their dates and the time between them. It
/// starts with the earliest and the latest photo, or with [a] and [b].
class PhotoCompareScreen extends ConsumerStatefulWidget {
  const PhotoCompareScreen({super.key, this.a, this.b});

  /// Ids of the photos to start with.
  final int? a;
  final int? b;

  @override
  ConsumerState<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends ConsumerState<PhotoCompareScreen> {
  late int? _a = widget.a;
  late int? _b = widget.b;

  Future<int?> _choose(List<ProgressPhoto> photos, ProgressPhoto current) =>
      showAppSheet<int>(
        context,
        (_) => _ChooseSheet(photos, selected: current.id),
      );

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider).value;
    final pair = photos == null ? null : comparePair(photos, a: _a, b: _b);
    final t = Theme.of(context).textTheme;

    Widget body() {
      if (photos == null) return const SizedBox.shrink();
      if (pair == null) {
        return const EmptyState(
          icon: AppIcons.gallery,
          title: 'Nothing to compare yet',
          message: 'Add at least two photos to see them side by side.',
        );
      }
      final (left, right) = pair;
      final sameDay = DateUtils.isSameDay(left.takenAt, right.takenAt);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sameDay
                  ? 'Same day'
                  : '${fmtSpan(left.takenAt, right.takenAt)} apart',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                for (final (photo, side) in [(left, true), (right, false)])
                  Expanded(
                    child: _Pane(
                      photo,
                      onChange: () async {
                        final id = await _choose(photos, photo);
                        if (id == null) return;
                        setState(() {
                          // Keep what's on screen for the other side.
                          _a = side ? id : left.id;
                          _b = side ? right.id : id;
                        });
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: body(),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane(this.photo, {required this.onChange});
  final ProgressPhoto photo;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final note = photo.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: Radii.smAll,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PhotoImage(photo, fit: BoxFit.contain, width: 480),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: onChange),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(photoDay.format(photo.takenAt), style: t.titleSmall),
        if (note != null)
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: muted),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onChange, child: const Text('Change')),
        ),
      ],
    );
  }
}

/// Every photo as a thumbnail to pick one from; pops with its id.
class _ChooseSheet extends StatelessWidget {
  const _ChooseSheet(this.photos, {required this.selected});
  final List<ProgressPhoto> photos;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text('Choose photo', style: t.titleLarge),
        ),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: Space.sm,
              crossAxisSpacing: Space.sm,
            ),
            itemCount: photos.length,
            itemBuilder: (_, i) {
              final p = photos[i];
              final on = p.id == selected;
              return Semantics(
                button: true,
                selected: on,
                label: 'Photo from ${photoDay.format(p.takenAt)}',
                excludeSemantics: true,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: Radii.smAll,
                    border: on
                        ? Border.all(color: scheme.primary, width: 3)
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: Radii.smAll,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PhotoImage(p, width: 160),
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
                              photoDay.format(p.takenAt),
                              style: t.labelSmall?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, p.id),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
