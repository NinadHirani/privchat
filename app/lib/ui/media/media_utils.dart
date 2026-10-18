import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/storage/media_store.dart';
import '../../models/models.dart';

/// Re-encodes photos: fixes orientation, resizes, and STRIPS ALL METADATA (EXIF GPS, camera model, timestamps).
Future<(Uint8List, Uint8List)> _processImage(Uint8List raw) async => compute(_processImageSync, raw);

(Uint8List, Uint8List) _processImageSync(Uint8List raw) {
  var im = img.decodeImage(raw);
  if (im == null) throw const FormatException('Unsupported image');
  im = img.bakeOrientation(im);
  if (im.width > 1600 || im.height > 1600) {
    im = im.width >= im.height ? img.copyResize(im, width: 1600) : img.copyResize(im, height: 1600);
  }
  im.exif = img.ExifData(); // belt and braces: no metadata survives
  final full = Uint8List.fromList(img.encodeJpg(im, quality: 82));
  final small = img.copyResize(im, width: 48);
  final thumb = Uint8List.fromList(img.encodeJpg(small, quality: 50));
  return (full, thumb);
}

Uint8List _avatarSync(Uint8List raw) {
  var im = img.decodeImage(raw)!;
  im = img.bakeOrientation(im);
  final s = im.width < im.height ? im.width : im.height;
  im = img.copyCrop(im, x: (im.width - s) ~/ 2, y: (im.height - s) ~/ 2, width: s, height: s);
  im = img.copyResize(im, width: 192);
  return Uint8List.fromList(img.encodeJpg(im, quality: 75));
}

class MediaUtils {
  static Future<Attachment> importImage(String path) async {
    final (full, thumb) = await _processImage(await File(path).readAsBytes());
    return MediaStore.importBytes(full, name: 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg', mime: 'image/jpeg', thumb: thumb);
  }

  static Future<Attachment> importVideo(String path) async =>
      MediaStore.importFile(File(path), name: 'VID_${DateTime.now().millisecondsSinceEpoch}${p.extension(path).isEmpty ? '.mp4' : p.extension(path)}',
          mime: 'video/mp4');

  static Future<Attachment> importDocument(String path, String name) async =>
      MediaStore.importFile(File(path), name: name, mime: mimeFor(name));

  static Future<Attachment> importAudio(String path, {String mime = 'audio/mp4'}) async {
    final a = await MediaStore.importFile(File(path), name: 'PTT_${DateTime.now().millisecondsSinceEpoch}.m4a', mime: mime);
    try {
      File(path).deleteSync(); // plaintext recording never lingers
    } catch (_) {}
    return a;
  }

  static Future<Uint8List> makeAvatar(String path) async => compute(_avatarSync, await File(path).readAsBytes());

  static String mimeFor(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.pdf': return 'application/pdf';
      case '.doc': return 'application/msword';
      case '.docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls': return 'application/vnd.ms-excel';
      case '.xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt': return 'application/vnd.ms-powerpoint';
      case '.pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.txt': return 'text/plain';
      case '.csv': return 'text/csv';
      case '.zip': return 'application/zip';
      case '.apk': return 'application/vnd.android.package-archive';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.mp4': return 'video/mp4';
      case '.mp3': return 'audio/mpeg';
      case '.m4a': return 'audio/mp4';
      default: return 'application/octet-stream';
    }
  }
}
