import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:family_memory/attachment_image_processor.dart';

void main() {
  group('attachment image safety', () {
    test('rejects a file that only pretends to be an image', () {
      expect(
        () => sanitizeAttachmentImage(
          Uint8List.fromList('not really a photo.jpg'.codeUnits),
        ),
        throwsA(
          isA<AttachmentImageException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_MAGIC_BYTES',
          ),
        ),
      );
    });

    test('rejects input above 5MiB before decoding', () {
      final bytes = Uint8List(maxAttachmentBytes + 1)
        ..setRange(0, 3, const [0xff, 0xd8, 0xff]);

      expect(
        () => sanitizeAttachmentImage(bytes),
        throwsA(
          isA<AttachmentImageException>().having(
            (error) => error.code,
            'code',
            'FILE_TOO_LARGE',
          ),
        ),
      );
    });

    test('bakes orientation and removes JPEG EXIF before upload', () {
      final sourceImage = img.Image(width: 2, height: 3);
      sourceImage.exif.imageIfd['Orientation'] = 6;
      sourceImage.exif.imageIfd['Make'] = 'PRIVATE_CAMERA';
      final sourceBytes = img.encodeJpg(sourceImage, quality: 90);

      final result = sanitizeAttachmentImage(sourceBytes);
      final decoded = img.decodeJpg(result.bytes)!;

      expect(result.format, AttachmentImageFormat.jpeg);
      expect(result.width, 3);
      expect(result.height, 2);
      expect(decoded.exif.isEmpty, isTrue);
      expect(decoded.iccProfile, isNull);
      expect(decoded.textData, isNull);
      expect(_containsAscii(result.bytes, 'PRIVATE_CAMERA'), isFalse);
      expect(result.sha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('removes PNG text metadata and preserves PNG magic bytes', () {
      final sourceImage = img.Image(width: 3, height: 2)
        ..textData = {'Comment': 'PRIVATE_LOCATION'};
      final sourceBytes = img.encodePng(sourceImage);

      final result = sanitizeAttachmentImage(sourceBytes);
      final decoded = img.decodePng(result.bytes)!;

      expect(result.format, AttachmentImageFormat.png);
      expect(result.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(decoded.textData, isNull);
      expect(decoded.exif.isEmpty, isTrue);
      expect(decoded.iccProfile, isNull);
      expect(_containsAscii(result.bytes, 'PRIVATE_LOCATION'), isFalse);
    });

    test('rejects dimensions above the database limit', () {
      final source = img.encodePng(
        img.Image(width: maxAttachmentDimension + 1, height: 1),
      );

      expect(
        () => sanitizeAttachmentImage(source),
        throwsA(
          isA<AttachmentImageException>().having(
            (error) => error.code,
            'code',
            'INVALID_DIMENSIONS',
          ),
        ),
      );
    });
  });
}

bool _containsAscii(Uint8List bytes, String value) {
  final pattern = value.codeUnits;
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
