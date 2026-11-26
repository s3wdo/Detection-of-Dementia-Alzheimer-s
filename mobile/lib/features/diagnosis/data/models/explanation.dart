import 'dart:convert';
import 'dart:typed_data';

/// The model's Grad-CAM map for one analysis, made by the server.
/// [image] is what the model analysed (the brain after masking);
/// [heatmap] is the map in the JET colour scale, the same size.
class Explanation {
  const Explanation({required this.method, required this.targetLabel, required this.image, required this.heatmap});

  final String method;
  final String targetLabel;
  final Uint8List image;
  final Uint8List heatmap;

  factory Explanation.fromJson(Map<String, dynamic> json) => Explanation(
        method: json['method'] as String,
        targetLabel: json['target_label'] as String,
        image: base64Decode(json['image_base64'] as String),
        heatmap: base64Decode(json['heatmap_base64'] as String),
      );
}
