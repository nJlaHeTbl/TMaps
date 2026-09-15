import 'package:flutter/material.dart';

import '../presentation/app_motion.dart';

/// The same short transition for every TMaps sheet, including reduced motion.
/// Flutter still owns dragging, focus, dismissal and the typed route result.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  bool isScrollControlled = false,
  bool? showDragHandle,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  backgroundColor: backgroundColor,
  shape: shape,
  clipBehavior: clipBehavior,
  isScrollControlled: isScrollControlled,
  showDragHandle: showDragHandle,
  sheetAnimationStyle: AnimationStyle(
    duration: AppMotion.duration(context, AppMotion.panel),
    reverseDuration: AppMotion.duration(context, AppMotion.quick),
  ),
);
