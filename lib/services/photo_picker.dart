import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

enum PhotoSource { camera, gallery }

/// A picked image, already downscaled, and when it was taken if known.
typedef PickedPhoto = ({Uint8List bytes, DateTime? takenAt});

/// Takes or picks a photo with the `image_picker` plugin. The camera is the
/// system camera app, so the app itself needs no camera permission.
///
/// On Android the plugin shrinks the image before it gets here: it decodes it
/// at a reduced size, scales the long edge down to [maxEdge] px and writes a
/// JPEG at [quality] (a few hundred kB instead of several MB).
class PhotoPicker {
  const PhotoPicker();

  static const maxEdge = 1600.0;
  static const quality = 80;

  /// Null when cancelled. Throws a `PlatformException` when the source isn't
  /// available, e.g. a device without a camera app.
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: switch (source) {
        PhotoSource.camera => ImageSource.camera,
        PhotoSource.gallery => ImageSource.gallery,
      },
      maxWidth: maxEdge,
      maxHeight: maxEdge,
      imageQuality: quality,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file, null);
  }

  /// A camera photo whose result was lost when Android killed the app while
  /// the camera was open, if there is one.
  Future<PickedPhoto?> lost() async {
    try {
      final res = await ImagePicker().retrieveLostData();
      final file = res.isEmpty ? null : res.file;
      return file == null ? null : await _read(file, await file.lastModified());
    } catch (_) {
      return null;
    }
  }

  /// Reads the picker's temporary copy and removes it, never anything outside
  /// the cache folder.
  Future<PickedPhoto> _read(XFile file, DateTime? takenAt) async {
    final bytes = await file.readAsBytes();
    try {
      final cache = (await getTemporaryDirectory()).path;
      if (file.path.startsWith(cache)) await File(file.path).delete();
    } on FileSystemException {
      // The system clears the cache anyway.
    }
    return (bytes: bytes, takenAt: takenAt);
  }
}
