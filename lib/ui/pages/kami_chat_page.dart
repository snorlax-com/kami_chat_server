import 'package:flutter/material.dart';
import 'package:kami_face_oracle/ui/pages/developer_chat_page.dart';

/// 占い相談（統合チャット）。タブ内では [DeveloperChatPage] を表示。
class KamiChatPage extends StatelessWidget {
  const KamiChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DeveloperChatPage(embedInShell: true);
  }
}
