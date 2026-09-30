import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:camera_dazz/main.dart';

void main() {
  testWidgets('camera selector uses the supplied model previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CameraDazzApp());
    await tester.pump();

    expect(find.text('DAZZ'), findsOneWidget);
    expect(find.text('DCR'), findsWidgets);
    await tester.tap(find.text('冷冽数码 · 清晰闪光').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('选择相机'), findsOneWidget);
    expect(find.text('135 SR'), findsWidgets);
    await tester.tap(find.text('135 SR').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('选择相机'), findsNothing);
    expect(find.text('35mm 胶片 · 细腻肤色'), findsOneWidget);
  });
}
