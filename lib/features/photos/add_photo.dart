import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/photos.dart';
import '../../services/photo_picker.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'photo_dialogs.dart';
import 'photo_image.dart';

/// Takes or picks a photo, asks when it was taken and files it. Does nothing
/// when cancelled.
Future<void> addPhoto(BuildContext context, WidgetRef ref) async {
  final picker = ref.read(photoPickerProvider);
  final source = await showAppSheet<PhotoSource>(
    context,
    (_) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return;
  final PickedPhoto? picked;
  try {
    picked = await picker.pick(source);
  } on PlatformException {
    if (context.mounted) {
      toast(
        context,
        source == PhotoSource.camera
            ? 'No camera available'
            : 'Couldn’t open your photos',
      );
    }
    return;
  }
  if (picked == null || !context.mounted) return;
  await filePhoto(context, ref, picked);
}

/// Shows a picked [photo] with its date and a note, and stores it on Save.
Future<void> filePhoto(
  BuildContext context,
  WidgetRef ref,
  PickedPhoto photo,
) async {
  final service = ref.read(photoServiceProvider);
  final res = await showAppSheet<({DateTime takenAt, String? note})>(
    context,
    (_) => _DetailsSheet(photo),
  );
  if (res == null) return;
  try {
    await service.add(photo.bytes, takenAt: res.takenAt, note: res.note);
    if (context.mounted) toast(context, 'Photo added');
  } catch (_) {
    if (context.mounted) toast(context, 'Couldn’t save the photo');
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
        child: Text('Add photo', style: Theme.of(context).textTheme.titleLarge),
      ),
      ListTile(
        leading: const AppIcon(AppIcons.camera),
        title: const Text('Take photo'),
        onTap: () => Navigator.pop(context, PhotoSource.camera),
      ),
      ListTile(
        leading: const AppIcon(AppIcons.gallery),
        title: const Text('Choose from gallery'),
        onTap: () => Navigator.pop(context, PhotoSource.gallery),
      ),
      const SizedBox(height: Space.sm),
    ],
  );
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet(this.photo);
  final PickedPhoto photo;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  final _note = TextEditingController();
  late DateTime _takenAt = widget.photo.takenAt ?? DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final day = await askPhotoDate(context, _takenAt);
    if (day == null) return;
    setState(() => _takenAt = redate(_takenAt, day, DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(_takenAt, DateTime.now());
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New photo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: Radii.smAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(
                widget.photo.bytes,
                fit: BoxFit.contain,
                cacheHeight: 840,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox(height: 120),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickDate,
              icon: const AppIcon(AppIcons.calendar, size: IconSizes.sm),
              label: Text(today ? 'Today' : photoDay.format(_takenAt)),
            ),
          ),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxPhotoNote)],
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: Space.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Space.sm),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  takenAt: _takenAt,
                  note: cleanNote(_note.text),
                )),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
