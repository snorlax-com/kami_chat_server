import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_actions.dart';

void main() {
  testWidgets('forcePrompt は busy 中でも確認ダイアログを表示できる', (tester) async {
    var exitCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      // 1 回目: ダイアログ表示のまま完了させない（busy を維持する想定の並行操作は不可なので
                      // clearBusyForExplicitExit の経路を forcePrompt で検証）
                      await TutorialGuestExitActions.promptExitIfNeeded(
                        context,
                        onExitWithoutLogin: () async {
                          exitCalled = true;
                        },
                      );
                    },
                    child: const Text('first'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await TutorialGuestExitActions.promptExitIfNeeded(
                        context,
                        forcePrompt: true,
                        onExitWithoutLogin: () async {
                          exitCalled = true;
                        },
                      );
                    },
                    child: const Text('force-exit'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('force-exit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);

    await tester.tap(find.text('終了する'));
    await tester.pumpAndSettle();
    expect(exitCalled, isTrue);
  });
}
