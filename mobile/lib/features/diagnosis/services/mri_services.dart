import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models/mri_file.dart';

/// Chooses an MRI image. Behind an interface so tests can supply a file.
abstract interface class MriPicker {
  /// Null when the user cancels.
  Future<MriFile?> pick();
}

class GalleryMriPicker implements MriPicker {
  @override
  Future<MriFile?> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return MriFile(name: file.name, bytes: await file.readAsBytes());
  }
}

/// Decodes the image on the phone to read its size and check that it looks
/// like a grayscale MRI slice. Returns null when the image cannot be decoded.
abstract interface class MriInspector {
  Future<MriInspection?> inspect(Uint8List bytes);
}

class DecodingMriInspector implements MriInspector {
  @override
  Future<MriInspection?> inspect(Uint8List bytes) async {
    try {
      final int width, height;
      final ui.Codec codec;
      if (kIsWeb) {
        // ImageDescriptor.encoded is not available in the web engine, so the
        // browser build decodes the image once at full size instead.
        final full = await ui.instantiateImageCodec(bytes);
        final frame = (await full.getNextFrame()).image;
        width = frame.width;
        height = frame.height;
        frame.dispose();
        full.dispose();
        codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      } else {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        width = descriptor.width;
        height = descriptor.height;
        // A small copy is enough to sample colours.
        codec = await descriptor.instantiateCodec(targetWidth: 64);
      }
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      if (data == null) return null;

      var gray = 0, total = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
        final hi = [r, g, b].reduce((a, c) => a > c ? a : c);
        final lo = [r, g, b].reduce((a, c) => a < c ? a : c);
        if (hi - lo <= 12) gray++;
        total++;
      }
      return MriInspection(width: width, height: height, grayscaleRatio: total == 0 ? 0 : gray / total);
    } catch (_) {
      return null;
    }
  }
}

final mriPickerProvider = Provider<MriPicker>((ref) => GalleryMriPicker());
final mriInspectorProvider = Provider<MriInspector>((ref) => DecodingMriInspector());
