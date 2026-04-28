import 'package:flutter/widgets.dart';

class ResponsiveUtils {
  const ResponsiveUtils._();

  static bool isWideLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900;
  }
}
