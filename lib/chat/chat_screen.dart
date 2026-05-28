import 'package:flutter/material.dart';
import '../services/mesh_network.dart';
import '../services/customization_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final MeshNetworkManager _mesh = MeshNetworkManager.instance;
  final List<_ChatRoom> _rooms = [
    _ChatRoom(name: 'Личный чат', lastMsg: 'Привет! Как дела?', time: '10:32', unread: 2),
    _ChatRoom(name: 'Mesh: Устройства рядом', lastMsg: 'Поиск...', time: '09:15', unread: 0),
  ];

  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

    if (_selectedIndex < 0) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text('Чаты', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _buildChatList(bgColor, isDark),
      );
    }

    return _buildChatDetail(bgColor, isDark);
  }

  Widget _buildChatList(Color bgColor, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _rooms.length,
      itemBuilder: (context, i) {
        final room = _rooms[i];
        return Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: CustomizationService.instance.primaryColor,
              child: Text(room.name[0], style: const TextStyle(color: Colors.white)),
            ),
            title: Text(room.name, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text(room.lastMsg, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(room.time, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                if (room.unread > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${room.unread}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ],
            ),
            onTap: () {
              setState(() => _selectedIndex = i);
            },
          ),
        );
      },
    );
  }

  Widget _buildChatDetail(Color bgColor, bool isDark) {
    final room = _rooms[_selectedIndex];
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selectedIndex = -1),
        ),
        actions: [
          if (_selectedIndex == 1)
            IconButton(
              icon: const Icon(Icons.wifi_tethering),
              tooltip: 'Отправить через Mesh',
              onPressed: () => _sendViaMesh('Test mesh message'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: _mesh.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text('Нет сообщений', style: TextStyle(color: Colors.grey[500], fontSize: 18)),
                        Text('Mesh-сообщения будут отображаться здесь',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _mesh.messages.length,
                    itemBuilder: (context, i) {
                      final msg = _mesh.messages[i];
                      return _buildBubble(msg.content, msg.senderName, msg.timestamp, i % 2 == 0);
                    },
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : Colors.white,
              border: Border(
                top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Сообщение...',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0D1117) : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {
                        final text = _textController.text.trim();
                        if (text.isNotEmpty) {
                          _mesh.sendMessage(text);
                          _textController.clear();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(String text, String sender, DateTime time, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF6C63FF) : Colors.grey[700],
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : null,
            bottomLeft: !isMe ? const Radius.circular(4) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(sender, style: TextStyle(fontSize: 10, color: Colors.white60)),
              ),
            Text(text, style: const TextStyle(color: Colors.white)),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendViaMesh(String text) async {
    await _mesh.sendMessage(text);
    setState(() {});
  }
}

class _ChatRoom {
  final String name;
  final String lastMsg;
  final String time;
  final int unread;

  _ChatRoom({required this.name, required this.lastMsg, required this.time, this.unread = 0});
}
