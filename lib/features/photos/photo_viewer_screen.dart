import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/photos.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'photo_dialogs.dart';
import 'photo_image.dart';

/// A full-screen photo with pinch zoom. Swipe for the neighbours; the date and
/// note can be changed and the photo deleted.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({super.key, required this.photoId});
  final int photoId;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  PageController? _pages;

  /// The photo on screen. It keeps its place when the list changes.
  late int _id = widget.photoId;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  Future<void> _editDate(ProgressPhoto p) async {
    final day = await askPhotoDate(context, p.takenAt);
    if (day == null) return;
    await ref
        .read(photoRepoProvider)
        .setTakenAt(p.id, redate(p.takenAt, day, DateTime.now()));
  }

  Future<void> _editNote(ProgressPhoto p) async {
    final note = await askPhotoNote(context, p.note);
    if (note != null) await ref.read(photoRepoProvider).setNote(p.id, note);
  }

  Future<void> _delete(ProgressPhoto p) async {
    final ok = await confirm(
      context,
      title: 'Delete photo?',
      message: 'It’s removed from this device. This can’t be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final service = ref.read(photoServiceProvider);
    final router = GoRouter.of(context);
    await service.remove(p);
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider).value;
    if (photos == null) return Scaffold(appBar: AppBar());
    final index = photos.indexWhere((p) => p.id == _id);
    if (index < 0) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: AppIcons.gallery,
          title: 'Photo not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final pages = _pages ??= PageController(initialPage: index);
    // Changing a date reorders the list: follow the photo to its new place.
    if (pages.hasClients && pages.page?.round() != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pages.hasClients) pages.jumpToPage(index);
      });
    }
    final photo = photos[index];

    return Scaffold(
      appBar: AppBar(
        title: Text('${index + 1} of ${photos.length}'),
        actions: [
          if (photos.length >= 2)
            TextButton(
              onPressed: () =>
                  context.go('/progress/photos/compare?a=${photo.id}'),
              child: const Text('Compare'),
            ),
          IconButton(
            tooltip: 'Delete photo',
            icon: const AppIcon(AppIcons.trash),
            onPressed: () => _delete(photo),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() {
                _id = photos[i].id;
                _zoomed = false;
              }),
              findChildIndexCallback: (key) {
                final id = (key as ValueKey<int>).value;
                final i = photos.indexWhere((p) => p.id == id);
                return i < 0 ? null : i;
              },
              itemBuilder: (_, i) => _Zoomable(
                key: ValueKey(photos[i].id),
                photo: photos[i],
                onZoomed: (z) => setState(() => _zoomed = z),
              ),
            ),
          ),
          _Details(
            photo,
            onDate: () => _editDate(photo),
            onNote: () => _editNote(photo),
          ),
        ],
      ),
    );
  }
}

/// Pinch to zoom, double-tap to zoom in or reset.
class _Zoomable extends StatefulWidget {
  const _Zoomable({super.key, required this.photo, required this.onZoomed});
  final ProgressPhoto photo;
  final ValueChanged<bool> onZoomed;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> {
  static const _zoomIn = 2.5;
  final _ctrl = TransformationController();
  Offset _tap = Offset.zero;

  bool get _zoomed => _ctrl.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    _ctrl.value = _zoomed
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(_zoomIn, _zoomIn, 1)..setTranslationRaw(
            -(_zoomIn - 1) * _tap.dx,
            -(_zoomIn - 1) * _tap.dy,
            0,
          ));
    widget.onZoomed(_zoomed);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: (d) => _tap = d.localPosition,
    onDoubleTap: _toggle,
    child: InteractiveViewer(
      transformationController: _ctrl,
      maxScale: 5,
      onInteractionEnd: (_) => widget.onZoomed(_zoomed),
      child: PhotoImage(widget.photo, fit: BoxFit.contain),
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details(this.photo, {required this.onDate, required this.onNote});
  final ProgressPhoto photo;
  final VoidCallback onDate;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final note = photo.note;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDate,
                icon: const AppIcon(AppIcons.calendar, size: IconSizes.sm),
                label: Text(photoDay.format(photo.takenAt)),
              ),
            ),
            InkWell(
              borderRadius: Radii.smAll,
              onTap: onNote,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTap),
                child: Row(
                  children: [
                    AppIcon(AppIcons.note, size: IconSizes.sm, color: muted),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        note ?? 'Add a note',
                        style: t.bodyMedium?.copyWith(
                          color: note == null ? muted : null,
                        ),
                      ),
                    ),
                    AppIcon(AppIcons.edit, size: IconSizes.sm, color: muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
