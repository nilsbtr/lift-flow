import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';

final photoDay = DateFormat('d MMM y');

/// A stored progress photo. A missing or unreadable file shows a placeholder.
/// [width] is the displayed size, used to decode thumbnails small.
class PhotoImage extends ConsumerStatefulWidget {
  const PhotoImage(
    this.photo, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
  });

  final ProgressPhoto photo;
  final BoxFit fit;
  final double? width;

  @override
  ConsumerState<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends ConsumerState<PhotoImage> {
  late Future<File?> _file = _load();

  Future<File?> _load() =>
      ref.read(photoStorageProvider).file(widget.photo.fileName);

  @override
  void didUpdateWidget(PhotoImage old) {
    super.didUpdateWidget(old);
    if (old.photo.fileName != widget.photo.fileName) _file = _load();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const _Frame();
        }
        if (file == null) return const _Frame(missing: true);
        return Semantics(
          image: true,
          label: 'Progress photo, ${photoDay.format(widget.photo.takenAt)}',
          child: Image.file(
            file,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            cacheWidth: w == null
                ? null
                : (w * MediaQuery.devicePixelRatioOf(context)).round(),
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const _Frame(missing: true),
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({this.missing = false});
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final lift = LiftColors.of(context);
    return ColoredBox(
      color: lift.raised,
      child: missing
          ? Center(
              child: Semantics(
                label: 'Photo unavailable',
                child: AppIcon(AppIcons.gallery, color: lift.muted),
              ),
            )
          : null,
    );
  }
}
