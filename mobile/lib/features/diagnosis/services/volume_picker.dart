import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A full MRI scan file picked by the doctor (.nii or .nii.gz).
class VolumeFile {
  const VolumeFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

/// Rules checked on the phone before upload. The server checks the file again
/// (it must be a readable 3-D NIfTI scan).
class VolumeRules {
  /// Same limit as the server's MAX_VOLUME_BYTES.
  static const maxBytes = 64 * 1024 * 1024;

  static bool isNifti(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.nii') || lower.endsWith('.nii.gz');
  }

  /// Null when the file can be sent, otherwise the reason it cannot.
  static String? problem(VolumeFile file) {
    if (!isNifti(file.name)) return 'Choose a NIfTI scan: a .nii or .nii.gz file.';
    if (file.sizeBytes == 0) return 'The file is empty.';
    if (file.sizeBytes > maxBytes) return 'The file is larger than 64 MB.';
    return null;
  }
}

/// Opens the system file browser. Returns null when the doctor cancels.
typedef VolumePicker = Future<VolumeFile?> Function();

Future<VolumeFile?> _pickWithSystemBrowser() async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  return VolumeFile(name: file.name, bytes: await file.readAsBytes());
}

/// Replaced in tests.
final volumePickerProvider = Provider<VolumePicker>((ref) => _pickWithSystemBrowser);
