import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Supplies the popover anchor required by share_plus 10 on iPad.
class ShareService {
  static Rect get _origin {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  static Future<ShareResult> share(String text, {String? subject}) =>
      Share.share(text, subject: subject, sharePositionOrigin: _origin);

  static Future<ShareResult> shareXFiles(List<XFile> files, {String? text}) =>
      Share.shareXFiles(files, text: text, sharePositionOrigin: _origin);
}
