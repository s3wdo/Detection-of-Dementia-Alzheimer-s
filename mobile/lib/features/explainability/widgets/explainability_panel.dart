import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

enum ExplainView { original, heatmap, overlay }

/// Explainability viewer. With a Grad-CAM map from the backend it offers
/// Original / Heatmap / Overlay and an opacity slider. Until the model provides
/// one it shows a plain "not available yet" state and the original image only:
/// we never draw a heatmap the model did not produce.
class ExplainabilityPanel extends StatefulWidget {
  const ExplainabilityPanel({
    super.key,
    required this.image,
    this.heatmap,
    this.height = 280,
    this.showOpacity = false,
  });

  /// Shows the overlay-opacity slider under the image (explainability screen).
  final bool showOpacity;

  /// The MRI: with a map, the brain-only image the model analysed; without one, the upload.
  final Uint8List? image;

  /// Grad-CAM map from the server, in colour. Null when the model made none.
  final Uint8List? heatmap;
  final double height;

  @override
  State<ExplainabilityPanel> createState() => _ExplainabilityPanelState();
}

class _ExplainabilityPanelState extends State<ExplainabilityPanel> {
  ExplainView _view = ExplainView.original;
  double _opacity = 0.4; // the team's Grad-CAM script blends the map at 40%

  @override
  Widget build(BuildContext context) {
    final heatmap = widget.heatmap;
    // No model map yet: an honest text state plus the original image, and no
    // controls that would do nothing.
    if (heatmap == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Explainability map', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.xs),
        Text('Not available yet', style: AppTextStyles.label.copyWith(color: AppColors.pending)),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'There is no explainability map for this result. Maps are made by the connected model; '
          'simulated results and results from before maps were added have none.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text('Original MRI', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.sm),
        if (widget.image == null)
          const Text('No image is stored for this demo scan.', style: AppTextStyles.bodySmall)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Container(
              height: widget.height,
              color: Colors.black,
              child: Image.memory(widget.image!, fit: BoxFit.contain, semanticLabel: 'Uploaded MRI slice'),
            ),
          ),
      ]);
    }

    final tag = switch (_view) {
      ExplainView.original => 'BRAIN · MODEL INPUT',
      ExplainView.heatmap => 'HEATMAP',
      ExplainView.overlay => 'OVERLAY',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ExplainView>(
          segments: const [
            ButtonSegment(value: ExplainView.original, label: Text('Brain')),
            ButtonSegment(value: ExplainView.heatmap, label: Text('Heatmap')),
            ButtonSegment(value: ExplainView.overlay, label: Text('Overlay')),
          ],
          selected: {_view},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            height: widget.height,
            color: Colors.black,
            child: Stack(fit: StackFit.expand, children: [
              switch (_view) {
                ExplainView.original => widget.image == null
                    ? const _Placeholder(
                        icon: Icons.image_not_supported_outlined,
                        title: 'No image in demo data',
                        text: 'Images are shown for scans uploaded in this session.',
                      )
                    : Image.memory(widget.image!, fit: BoxFit.contain, semanticLabel: 'Uploaded MRI slice'),
                ExplainView.heatmap => Image.memory(heatmap, fit: BoxFit.contain, semanticLabel: 'Grad-CAM heatmap'),
                ExplainView.overlay => widget.image != null
                    ? Stack(fit: StackFit.expand, children: [
                        Image.memory(widget.image!, fit: BoxFit.contain),
                        Opacity(opacity: _opacity, child: Image.memory(heatmap, fit: BoxFit.contain)),
                      ])
                    : Image.memory(heatmap, fit: BoxFit.contain),
              },
              Positioned(
                left: AppSpacing.lg,
                top: AppSpacing.md,
                child: ExcludeSemantics(
                  child: Text(tag,
                      style: AppTextStyles.mono.copyWith(color: Colors.white, fontSize: 12.5, letterSpacing: 1.2)),
                ),
              ),
            ]),
          ),
        ),
        if (widget.showOpacity && _view == ExplainView.overlay) ...[
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            const Expanded(child: Text('Overlay opacity', style: AppTextStyles.label)),
            Text('${(_opacity * 100).round()}%', style: AppTextStyles.mono),
          ]),
          Slider(
            value: _opacity,
            label: '${(_opacity * 100).round()}%',
            onChanged: (v) => setState(() => _opacity = v),
          ),
        ],
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFF9AA6C2), size: 36),
          const SizedBox(height: AppSpacing.md),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: AppSpacing.xs),
          Text(text,
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC5CDE0), fontSize: 12, height: 1.4)),
        ]),
      ),
    );
  }
}
