import 'package:flutter/widgets.dart';

abstract final class AppLayoutMetrics {
  static const double bottomNavigationBarHeight = 52;

  static double bottomNavigationClearance(BuildContext context) {
    return bottomNavigationBarHeight + MediaQuery.paddingOf(context).bottom;
  }
}
