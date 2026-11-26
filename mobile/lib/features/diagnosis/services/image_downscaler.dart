import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;

/// The server accepts images up to this many pixels on each side.
const maxUploadSide = 256;

/// Returns [bytes] unchanged when the image already fits the server's limit;
/// otherwise a PNG scaled down to fit, keeping the aspect ratio.
///
/// Whether downscaling on the phone matches what the model was trained on is a
/// question for the model owner (see docs/backend.md). Images that already fit
/// are sent exactly as chosen.
Future<Uint8List> downscaleForUpload(Uint8List bytes) async {
  final (width, height) = await _size(bytes);
  if (width <= maxUploadSide && height <= maxUploadSide) return bytes;
  final scale = maxUploadSide / (width > height ? width : height);
  final targetWidth = (width * scale).round().clamp(1, maxUploadSide);
  final targetHeight = (height * scale).round().clamp(1, maxUploadSide);
  final ui.Codec codec;
  ui.ImageDescriptor? descriptor;
  if (kIsWeb) {
    codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth, targetHeight: targetHeight);
  } else {
    descriptor = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(bytes));
    codec = await descriptor.instantiateCodec(targetWidth: targetWidth, targetHeight: targetHeight);
  }
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  codec.dispose();
  descriptor?.dispose();
  if (png == null) throw StateError('The image could not be prepared for upload.');
  return png.buffer.asUint8List();
}

/// Width and height of an encoded image. ImageDescriptor.encoded is not
/// available in the web engine, so the browser build decodes the image instead.
Future<(int, int)> _size(Uint8List bytes) async {
  if (kIsWeb) {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final size = (image.width, image.height);
    image.dispose();
    codec.dispose();
    return size;
  }
  final descriptor = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(bytes));
  final size = (descriptor.width, descriptor.height);
  descriptor.dispose();
  return size;
}
