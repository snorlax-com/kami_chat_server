import 'package:flutter/material.dart';
import 'package:kami_face_oracle/models/personality_type_detail.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/deities.dart';

/// 柱とのチャットページ
class PillarChatPage extends StatefulWidget {
  final int personalityType;
  final String? pillarId;

  const PillarChatPage({
    super.key,
    required this.personalityType,
    this.pillarId,
  });

  @override
  State<PillarChatPage> createState() => _PillarChatPageState();
}

class _PillarChatPageState extends State<PillarChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  PersonalityTypeDetail? _detail;
  String? _characterImagePath;
  String? _pillarTitle;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetailAndHistory();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetailAndHistory() async {
    try {
      final detail = await PersonalityTypeDetailService.getDetail(widget.personalityType);
      if (detail != null) {
        setState(() {
          _detail = detail;
          _characterImagePath = detail.characterImage.isNotEmpty
              ? detail.characterImage
              : (widget.pillarId != null && widget.pillarId!.isNotEmpty
                  ? 'assets/characters/${widget.pillarId!.toLowerCase()}.png'
                  : 'assets/characters/shisaru.png');
          _pillarTitle = detail.pillarTitle.isNotEmpty ? detail.pillarTitle : '';
        });

        // 詳細ページで表示された内容を履歴として追加
        final historyMessages = <ChatMessage>[];
        for (final entry in detail.orderedSections) {
          final section = entry.value;
          historyMessages.add(ChatMessage(
            text: '${section.title}\n\n${section.content}',
            isFromPillar: true,
            timestamp: DateTime.now(),
          ));
        }

        // 最後に指定されたメッセージを追加
        historyMessages.add(ChatMessage(
          text:
              '隠占として降臨した柱に占ってほしいことや悩みを相談したいことがあれば、チャットで教えてくださいね！柱の性格とあなたの性格を考慮して、AIでなく創始者である人間があなたの質問に柱を通してお答えします！例　今年の運勢・今の個々の問題の解決法など',
          isFromPillar: true,
          timestamp: DateTime.now(),
        ));

        setState(() {
          _messages = historyMessages;
          _isLoading = false;
        });

        // スクロールを最下部に
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[PillarChatPage] エラー: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isFromPillar: false,
        timestamp: DateTime.now(),
      ));
    });

    _messageController.clear();

    // スクロールを最下部に
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // TODO: サーバーにメッセージを送信して応答を取得
    // 現在はプレースホルダーとして、後で実装
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('柱とのチャット'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final iconPath = _characterImagePath ?? 'assets/characters/shisaru.png';

    return Scaffold(
      appBar: AppBar(
        title: Text(_pillarTitle ?? '柱とのチャット'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.3),
                const Color(0xFF06B6D4).withOpacity(0.2),
                const Color(0xFF0A0E1A),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 神秘的な背景
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  colors: [
                    const Color(0xFF8B5CF6).withOpacity(0.2),
                    const Color(0xFF06B6D4).withOpacity(0.15),
                    const Color(0xFF0A0E1A).withOpacity(0.9),
                    const Color(0xFF000000),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                  radius: 1.5,
                ),
              ),
            ),
          ),
          // チャットコンテンツ
          Column(
            children: [
              // メッセージリスト
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _buildChatMessage(
                      message: message,
                      characterImagePath: iconPath,
                      isFirst: index == 0,
                    );
                  },
                ),
              ),
              // 入力エリア
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'メッセージを入力...',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _sendMessage,
                            icon: const Icon(Icons.send, color: Colors.white),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// チャットメッセージを構築
  Widget _buildChatMessage({
    required ChatMessage message,
    required String characterImagePath,
    bool isFirst = false,
  }) {
    if (message.isFromPillar) {
      // 柱からのメッセージ
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 柱のアイコン
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(right: 12, top: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF8B5CF6).withOpacity(0.6),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  characterImagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.face,
                        color: Colors.white70,
                        size: 28,
                      ),
                    );
                  },
                ),
              ),
            ),
            // チャットバブル
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F3A).withOpacity(0.8),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(4),
                    topRight: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                    bottomLeft: const Radius.circular(18),
                  ),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 柱の名前（最初のメッセージのみ）
                    if (isFirst && _pillarTitle != null && _pillarTitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.star,
                              size: 14,
                              color: const Color(0xFF8B5CF6).withOpacity(0.9),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _pillarTitle!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8B5CF6).withOpacity(0.9),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // メッセージ本文
                    Text(
                      message.text,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 15,
                        height: 1.6,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      );
    } else {
      // ユーザーからのメッセージ
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 40),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.8),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(4),
                    bottomRight: const Radius.circular(18),
                    bottomLeft: const Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15,
                    height: 1.6,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

/// チャットメッセージのモデル
class ChatMessage {
  final String text;
  final bool isFromPillar;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isFromPillar,
    required this.timestamp,
  });
}
