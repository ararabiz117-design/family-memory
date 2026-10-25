import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

const int maxAttachmentBytes = 5 * 1024 * 1024;
const int maxAttachmentDimension = 4096;
const int attachmentUploadMaxDimension = 1600;

enum AttachmentImageFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png');

  const AttachmentImageFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

class AttachmentImageException implements Exception {
  const AttachmentImageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class SanitizedAttachmentImage {
  const SanitizedAttachmentImage({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.sha256Hex,
  });

  final Uint8List bytes;
  final AttachmentImageFormat format;
  final int width;
  final int height;
  final String sha256Hex;

  String get mimeType => format.mimeType;
  String get extension => format.extension;
  int get byteSize => bytes.length;
}

/// Validates and rewrites a selected image before it leaves the device.
///
/// Re-encoding copies pixel data only. EXIF (including GPS), ICC profiles,
/// comments, PNG text chunks, and embedded thumbnails are deliberately not
/// copied to the returned bytes. EXIF orientation is applied to the pixels
/// first so that removing it does not rotate the displayed image.
SanitizedAttachmentImage sanitizeAttachmentImage(Uint8List source) {
  if (source.isEmpty) {
    throw const AttachmentImageException('EMPTY_FILE', '空のファイルは追加できません。');
  }
  if (source.length > maxAttachmentBytes) {
    throw const AttachmentImageException(
      'FILE_TOO_LARGE',
      '画像は5MiB以下を選んでください。',
    );
  }

  final format = _formatFromMagicBytes(source);
  final decoder = switch (format) {
    AttachmentImageFormat.jpeg => img.JpegDecoder(),
    AttachmentImageFormat.png => img.PngDecoder(),
  };

  late final img.DecodeInfo info;
  try {
    final decodedInfo = decoder.startDecode(source);
    if (decodedInfo == null) {
      throw const AttachmentImageException(
        'INVALID_IMAGE',
        '画像ファイルが壊れているか、対応していない形式です。',
      );
    }
    info = decodedInfo;
  } on AttachmentImageException {
    rethrow;
  } catch (_) {
    throw const AttachmentImageException(
      'INVALID_IMAGE',
      '画像ファイルが壊れているか、対応していない形式です。',
    );
  }

  if (info.width < 1 ||
      info.height < 1 ||
      info.width > maxAttachmentDimension ||
      info.height > maxAttachmentDimension) {
    throw const AttachmentImageException(
      'INVALID_DIMENSIONS',
      '画像の縦横はそれぞれ4096px以下にしてください。',
    );
  }
  if (info.numFrames != 1) {
    throw const AttachmentImageException(
      'MULTI_FRAME_IMAGE',
      'アニメーション画像には対応していません。',
    );
  }

  late final img.Image decoded;
  try {
    final value = decoder.decode(source);
    if (value == null) {
      throw const AttachmentImageException(
        'INVALID_IMAGE',
        '画像ファイルを読み取れませんでした。',
      );
    }
    decoded = value;
  } on AttachmentImageException {
    rethrow;
  } catch (_) {
    throw const AttachmentImageException('INVALID_IMAGE', '画像ファイルを読み取れませんでした。');
  }

  var pixels = img.bakeOrientation(decoded)
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  if (pixels.width > maxAttachmentDimension ||
      pixels.height > maxAttachmentDimension) {
    throw const AttachmentImageException(
      'INVALID_DIMENSIONS',
      '画像の縦横はそれぞれ4096px以下にしてください。',
    );
  }

  if (pixels.width > attachmentUploadMaxDimension ||
      pixels.height > attachmentUploadMaxDimension) {
    pixels = img.copyResize(
      pixels,
      width: pixels.width >= pixels.height
          ? attachmentUploadMaxDimension
          : null,
      height: pixels.height > pixels.width
          ? attachmentUploadMaxDimension
          : null,
      interpolation: img.Interpolation.average,
    );
  }

  final rewritten = switch (format) {
    AttachmentImageFormat.jpeg => img.encodeJpg(pixels, quality: 82),
    AttachmentImageFormat.png => img.encodePng(pixels, level: 6),
  };
  if (rewritten.isEmpty || rewritten.length > maxAttachmentBytes) {
    throw const AttachmentImageException(
      'SANITIZED_FILE_TOO_LARGE',
      '安全処理後の画像が5MiBを超えました。別の画像を選んでください。',
    );
  }

  return SanitizedAttachmentImage(
    bytes: rewritten,
    format: format,
    width: pixels.width,
    height: pixels.height,
    sha256Hex: sha256.convert(rewritten).toString(),
  );
}

AttachmentImageFormat _formatFromMagicBytes(Uint8List bytes) {
  const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= pngSignature.length) {
    var png = true;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) {
        png = false;
        break;
      }
    }
    if (png) return AttachmentImageFormat.png;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return AttachmentImageFormat.jpeg;
  }
  throw const AttachmentImageException(
    'UNSUPPORTED_MAGIC_BYTES',
    'JPGまたはPNG画像を選んでください。拡張子だけを変更したファイルは追加できません。',
  );
}
