import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/od_request.dart';
import 'api_client.dart';

/// Picks, compresses and uploads certificates and prize photos.
///
/// Compression happens on the device before anything leaves it. A modern phone
/// photo is 8-12 MB; resized to fit 1600px and re-encoded as JPEG it lands
/// around 200-600 KB, which keeps the upload fast on college wifi and keeps
/// storage use sane. PDFs are sent as they are - re-encoding them would lose
/// the document.
class UploadService {
  static final _picker = ImagePicker();

  /// Picks an image from the camera or gallery and uploads it.
  /// Returns the stored file, or null if the picker was dismissed.
  static Future<ODFile?> pickAndUploadImage({
    required String requestId,
    required String kind,
    required ImageSource source,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      // A first pass at pick time; the real work is done below.
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 92,
    );
    if (picked == null) return null;

    final original = File(picked.path);
    final compressed = await _compress(original);

    try {
      return await _upload(
        requestId: requestId,
        kind: kind,
        bytes: compressed.bytes,
        mimeType: 'image/jpeg',
        fileName: _name(picked.name, 'jpg'),
      );
    } finally {
      // Clean up whatever we wrote to the cache while compressing.
      if (compressed.tempFile != null) {
        try {
          await compressed.tempFile!.delete();
        } catch (_) {}
      }
    }
  }

  /// Uploads a PDF or image the user chose from their files, unchanged except
  /// for images, which are still compressed.
  static Future<ODFile> uploadFile({
    required String requestId,
    required String kind,
    required File file,
    required String mimeType,
    required String fileName,
  }) async {
    if (mimeType.startsWith('image/')) {
      final compressed = await _compress(file);
      try {
        return await _upload(
          requestId: requestId,
          kind: kind,
          bytes: compressed.bytes,
          mimeType: 'image/jpeg',
          fileName: _name(fileName, 'jpg'),
        );
      } finally {
        if (compressed.tempFile != null) {
          try {
            await compressed.tempFile!.delete();
          } catch (_) {}
        }
      }
    }

    final bytes = await file.readAsBytes();
    if (bytes.length > AppConfig.maxUploadBytes) {
      throw ApiException(
        'That file is ${_mb(bytes.length)} MB. The limit is '
        '${AppConfig.maxUploadBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return _upload(
      requestId: requestId,
      kind: kind,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
    );
  }

  static Future<({Uint8List bytes, File? tempFile})> _compress(File source) async {
    final dir = await getTemporaryDirectory();
    final target =
        '${dir.path}/od_${DateTime.now().microsecondsSinceEpoch}.jpg';

    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        quality: AppConfig.imageQuality,
        minWidth: AppConfig.imageMaxDimension,
        minHeight: AppConfig.imageMaxDimension,
        format: CompressFormat.jpeg,
        // Phones record orientation in EXIF rather than rotating the pixels;
        // without this a portrait photo arrives sideways.
        autoCorrectionAngle: true,
      );

      if (result != null) {
        final file = File(result.path);
        final bytes = await file.readAsBytes();
        if (bytes.length <= AppConfig.maxUploadBytes) {
          return (bytes: bytes, tempFile: file);
        }
        // Still too big: try again harder before giving up.
        final harder = await FlutterImageCompress.compressWithFile(
          result.path,
          quality: 60,
          minWidth: 1200,
          minHeight: 1200,
          format: CompressFormat.jpeg,
        );
        if (harder != null && harder.length <= AppConfig.maxUploadBytes) {
          return (bytes: harder, tempFile: file);
        }
        throw ApiException(
          'That image is too large to upload even after compression. '
          'Please use a smaller photo.',
        );
      }
    } catch (err) {
      if (err is ApiException) rethrow;
      // Compression is a convenience; fall through to the original file rather
      // than blocking the upload on a device where the plugin misbehaves.
      debugPrint('image compression failed, sending original: $err');
    }

    final bytes = await source.readAsBytes();
    if (bytes.length > AppConfig.maxUploadBytes) {
      throw ApiException(
        'That image is ${_mb(bytes.length)} MB and could not be compressed. '
        'Please use a smaller photo.',
      );
    }
    return (bytes: bytes, tempFile: null);
  }

  static Future<ODFile> _upload({
    required String requestId,
    required String kind,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    final res = await ApiClient.call('UPLOAD_FILE', payload: {
      'reqId': requestId,
      'kind': kind,
      'mimeType': mimeType,
      'fileName': fileName,
      'data': base64Encode(bytes),
    });
    return ODFile.fromJson(res['file'] as Map<String, dynamic>);
  }

  /// A short-lived URL for viewing an attached file.
  static Future<String> viewUrl(String fileId) async {
    final res = await ApiClient.call('FILE_URL', payload: {'fileId': fileId});
    return res['url'].toString();
  }

  static Future<void> delete(String fileId) async {
    await ApiClient.call('DELETE_FILE', payload: {'fileId': fileId});
  }

  static String _name(String original, String ext) {
    final base = original.split(RegExp(r'[\\/]')).last;
    final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return '${safe.isEmpty ? 'upload' : safe}.$ext';
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
