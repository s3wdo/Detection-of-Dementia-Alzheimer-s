import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/data/repository_providers.dart';
import '../../diagnosis/data/analyses_repository.dart';

/// Hands a PDF to the phone: on iPhone the share sheet (Save to Files, Mail,
/// AirDrop, Print). [origin] anchors the sheet on iPad.
typedef ReportSharer = Future<void> Function(ReportFile file, Rect? origin);

final reportSharerProvider = Provider<ReportSharer>((ref) => (file, origin) async {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(file.bytes, mimeType: 'application/pdf', name: file.filename)],
        fileNameOverrides: [file.filename],
        subject: file.filename,
        sharePositionOrigin: origin,
      ));
    });

/// Downloads the report PDF for [analysisId] from the server and opens the
/// share sheet. The server decides which version the user gets.
Future<void> downloadReportPdf(BuildContext context, WidgetRef ref, String analysisId) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Preparing the PDF…'), duration: Duration(seconds: 20)));
  try {
    final file = await ref.read(analysesRepositoryProvider).reportPdf(analysisId);
    messenger.hideCurrentSnackBar();
    await ref.read(reportSharerProvider)(file, origin);
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not download the PDF. $e')));
  }
}
