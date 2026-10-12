import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/photos.dart';
import '../../domain/stats.dart';

/// Asks for the day a photo was taken, never later than today. Null when
/// cancelled.
Future<DateTime?> askPhotoDate(BuildContext context, DateTime initial) {
  final today = dayOf(DateTime.now());
  final day = dayOf(initial);
  return showDatePicker(
    context: context,
    initialDate: day.isAfter(today) ? today : day,
    firstDate: DateTime(2000),
    lastDate: today,
  );
}

/// Asks for a note. Returns the text (blank clears it), or null when
/// cancelled.
Future<String?> askPhotoNote(BuildContext context, String? initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Note'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(kMaxPhotoNote)],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
