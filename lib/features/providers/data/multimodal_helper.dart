import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../core/models/chat_models.dart';

class EncodedImageAttachment {
  const EncodedImageAttachment({
    required this.mimeType,
    required this.base64Data,
    this.name,
  });

  final String mimeType;
  final String base64Data;
  final String? name;

  String get dataUri => 'data:$mimeType;base64,$base64Data';
}

class MultimodalHelper {
  /// Reads and encodes image attachments safely, resizing if too large.
  static List<EncodedImageAttachment> extractImageAttachments(
    List<AttachmentMeta> attachments, {
    int maxDimension = 2048,
    int maxBytes = 2 * 1024 * 1024, // 2MB
  }) {
    final results = <EncodedImageAttachment>[];
    for (final att in attachments) {
      if (!att.isImage) continue;
      try {
        final file = File(att.path);
        if (!file.existsSync()) continue;

        var bytes = file.readAsBytesSync();
        var mime = att.mimeType.isNotEmpty ? att.mimeType : 'image/jpeg';
        if (mime == 'image/jpg') mime = 'image/jpeg';

        // Check if downscale is needed
        if (bytes.length > maxBytes) {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            var targetW = decoded.width;
            var targetH = decoded.height;
            if (targetW > maxDimension || targetH > maxDimension) {
              if (targetW > targetH) {
                targetH = (targetH * (maxDimension / targetW)).round();
                targetW = maxDimension;
              } else {
                targetW = (targetW * (maxDimension / targetH)).round();
                targetH = maxDimension;
              }
            }
            final resized = img.copyResize(decoded, width: targetW, height: targetH);
            bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
            mime = 'image/jpeg';
          }
        }

        final b64 = base64Encode(bytes);
        results.add(EncodedImageAttachment(
          mimeType: mime,
          base64Data: b64,
          name: att.name,
        ));
      } catch (e) {
        debugPrint('[MultimodalHelper] Failed to read image attachment ${att.path}: $e');
      }
    }
    return results;
  }
}
