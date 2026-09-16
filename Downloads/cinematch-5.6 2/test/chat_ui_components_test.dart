import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/widgets/chat_ui_components.dart';

void main() {
  testWidgets('Mesaj yanıt özeti ve reaksiyon sayısı birlikte gösterilir', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageRow(
            text: 'Ben de aynı fikirdeyim.',
            isMine: true,
            authorId: 'me',
            currentUserId: 'me',
            replyTo: const {
              'messageId': 'older-message',
              'authorName': 'Atacool',
              'text': 'Bu filmi kesinlikle izlemeliyiz.',
            },
            reactions: const {
              '❤️': ['me', 'friend'],
            },
          ),
        ),
      ),
    );

    expect(find.text('Atacool'), findsOneWidget);
    expect(find.text('Bu filmi kesinlikle izlemeliyiz.'), findsOneWidget);
    expect(find.text('❤️ 2'), findsOneWidget);
  });
}
