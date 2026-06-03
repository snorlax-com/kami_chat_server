import 'package:flutter/material.dart';

/// 定期購入サブスク未加入時にストアタブへ表示するロック画面。
class StoreLockedPage extends StatelessWidget {
  const StoreLockedPage({super.key, this.embedInShell = false});

  final bool embedInShell;

  @override
  Widget build(BuildContext context) {
    const body = Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'ストアはサブスクご加入中のみご利用いただけます',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'サブスクを解約した場合、ストアはご利用いただけません。\n'
              '再度ご利用になるには、占い相談からサブスクへご加入ください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
    if (embedInShell) return body;
    return Scaffold(appBar: AppBar(title: const Text('ストア')), body: body);
  }
}
