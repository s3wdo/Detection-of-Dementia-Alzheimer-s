import 'dart:typed_data';

/// An MRI image chosen on the phone, before upload.
class MriFile {
  const MriFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  /// Detected from the file's first bytes (not its name), like the backend does.
  MriFormat get format {
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return MriFormat.png;
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return MriFormat.jpeg;
    return MriFormat.unsupported;
  }
}

enum MriFormat {
  png('PNG'),
  jpeg('JPG'),
  unsupported('Unsupported');

  const MriFormat(this.label);
  final String label;
}

/// What the app could learn by decoding the image on the phone.
class MriInspection {
  const MriInspection({required this.width, required this.height, required this.grayscaleRatio});

  final int width;
  final int height;

  /// Share of sampled pixels whose R, G and B are nearly equal (0–1).
  /// MRI slices are grayscale, so a low value suggests a wrong image.
  final double grayscaleRatio;
}

enum CheckStatus { passed, warning, failed }

typedef MriCheck = ({String label, String detail, CheckStatus status});

/// Upload rules from the plan: JPG/PNG only, at most 10 MB, must decode,
/// and should look like a grayscale MRI slice (warning only — the doctor decides).
abstract final class MriRules {
  static const maxBytes = 10 * 1024 * 1024;
  static const minSide = 64;
  static const minGrayscaleRatio = 0.9;

  static List<MriCheck> check(MriFile file, MriInspection? inspection) {
    final mb = (file.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return [
      (
        label: 'Supported format',
        detail: file.format == MriFormat.unsupported ? 'Only JPG and PNG images are supported' : file.format.label,
        status: file.format == MriFormat.unsupported ? CheckStatus.failed : CheckStatus.passed,
      ),
      (
        label: 'File size under 10 MB',
        detail: '$mb MB',
        status: file.sizeBytes <= maxBytes ? CheckStatus.passed : CheckStatus.failed,
      ),
      (
        label: 'Image readable',
        detail: inspection == null ? 'The image could not be opened' : '${inspection.width} × ${inspection.height} px',
        status: inspection == null || inspection.width < minSide || inspection.height < minSide
            ? CheckStatus.failed
            : CheckStatus.passed,
      ),
      (
        label: 'Looks like a grayscale MRI slice',
        detail: inspection == null
            ? 'Not checked'
            : inspection.grayscaleRatio >= minGrayscaleRatio
                ? 'Passed'
                : 'This image may not be a suitable MRI slice. Please verify it.',
        status: inspection == null
            ? CheckStatus.failed
            : inspection.grayscaleRatio >= minGrayscaleRatio
                ? CheckStatus.passed
                : CheckStatus.warning,
      ),
    ];
  }

  /// Analysis may start when no check failed (warnings are allowed).
  static bool canAnalyze(List<MriCheck> checks) => checks.every((c) => c.status != CheckStatus.failed);
}
