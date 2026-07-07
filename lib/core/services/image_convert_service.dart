import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum ImageOutFormat { jpg, png }

enum ImageMaxSize { original, px2048, px1080 }

extension ImageMaxSizeValue on ImageMaxSize {
  int? get maxDim {
    switch (this) {
      case ImageMaxSize.original:
        return null;
      case ImageMaxSize.px2048:
        return 2048;
      case ImageMaxSize.px1080:
        return 1080;
    }
  }
}

/// Pure-Dart image conversion (isolate per image): decode anything the
/// `image` package reads (JPG/PNG/WebP/BMP/GIF/TIFF), bake EXIF
/// orientation, optionally downscale, re-encode as JPG or PNG.
/// WebP *encoding* is not possible in pure Dart — outputs are JPG/PNG only.
class ImageConvertService {
  ImageConvertService._();

  static Future<Uint8List> convert(
    Uint8List raw, {
    required ImageOutFormat format,
    int jpgQuality = 88,
    int? maxDim,
  }) {
    return compute(_convert, _ConvertArgs(raw, format, jpgQuality, maxDim));
  }
}

class _ConvertArgs {
  final Uint8List raw;
  final ImageOutFormat format;
  final int jpgQuality;
  final int? maxDim;
  const _ConvertArgs(this.raw, this.format, this.jpgQuality, this.maxDim);
}

Uint8List _convert(_ConvertArgs args) {
  final decoded = img.decodeImage(args.raw);
  if (decoded == null) throw Exception('Unsupported image format');
  var image = img.bakeOrientation(decoded);
  final maxDim = args.maxDim;
  if (maxDim != null && (image.width > maxDim || image.height > maxDim)) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxDim, interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: maxDim, interpolation: img.Interpolation.average);
  }
  switch (args.format) {
    case ImageOutFormat.jpg:
      return Uint8List.fromList(img.encodeJpg(image, quality: args.jpgQuality));
    case ImageOutFormat.png:
      return Uint8List.fromList(img.encodePng(image));
  }
}
