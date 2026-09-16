import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/screens/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Ön yüklenen son aramalar ilk karede filtrelerin altında görünür',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'unified_search_recents_v1': [
          jsonEncode({
            'kind': 'movie',
            'id': '550',
            'title': 'Dövüş Kulübü',
            'subtitle': '1999',
          }),
        ],
      });
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await SearchPage.preloadRecents();
      await tester.pumpWidget(const MaterialApp(home: SearchPage()));

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Hepsi'), findsOneWidget);
      expect(find.text('Filmler'), findsOneWidget);
      expect(find.text('Oyuncular'), findsOneWidget);
      expect(find.text('Yönetmenler'), findsOneWidget);
      expect(find.text('Kullanıcılar'), findsOneWidget);
      expect(find.text('Son Aramalar'), findsOneWidget);
      expect(find.text('Dövüş Kulübü'), findsOneWidget);

      final filterBottom = tester.getBottomLeft(find.text('Hepsi')).dy;
      final recentTitleTop = tester.getTopLeft(find.text('Son Aramalar')).dy;
      expect(filterBottom, lessThan(recentTitleTop));
    },
  );
}
