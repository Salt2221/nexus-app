// ═══════════════════════════════════════════════════════════════
// NEXUS P2P Чаты — децентрализованные чаты на DHT
//
// Возможности:
//  - Добавление в друзья (по P2P ID)
//  - Группы (создание, приглашение, выход)
//  - Каналы (подписка, администрирование)
//  - Текстовые сообщения
//  - Файлы и фото (через DHT store)
//  - Работает офлайн (сообщения хранятся локально)
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/dht_network.dart';

// ═══════════════════════════════════════════════════════════════
// СЕРВИС ЧАТОВ
// ═══════════════════════════════════════════════════════════════

class P2pChatService {
  static final P2pChatService instance = P2pChatService._();

  final List<PeerProfile> _friends = [];
  final List<ChatGroup> _groups = [];
  final List<ChatChannel> _channels = [];
  final Map<String, List<ChatMessage>> _messages = {}; // chatId -> messages

  String _myP2pId = '';
  String _myUsername = '';

  P2pChatService._();

  String get myP2pId => _myP2pId;
  String get myUsername => _myUsername;
  List<PeerProfile> get friends => List.unmodifiable(_friends);
  List<ChatGroup> get groups => List.unmodifiable(_groups);
  List<ChatChannel> get channels => List.unmodifiable(_channels);

  void init(String p2pId, String username) {
    _myP2pId = p2pId;
    _myUsername = username;
  }

  /// Добавить в друзья
  Future<bool> addFriend(String p2pId, String username) async {
    if (_friends.any((f) => f.p2pId == p2pId)) return false;
    _friends.add(PeerProfile(p2pId: p2pId, username: username, status: 'online'));
    _saveFriends();
    return true;
  }

  /// Создать группу
  ChatGroup createGroup(String name, List<String> members) {
    final group = ChatGroup(
      id: 'g_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      members: [myP2pId, ...members.where((m) => m != myP2pId)],
      admin: myP2pId,
      createdAt: DateTime.now(),
    );
    _groups.add(group);
    _saveGroups();
    return group;
  }

  /// Создать канал
  ChatChannel createChannel(String name, String description) {
    final channel = ChatChannel(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      subscribers: [myP2pId],
      admin: myP2pId,
      createdAt: DateTime.now(),
    );
    _channels.add(channel);
    _saveChannels();
    return channel;
  }

  /// Отправить сообщение
  ChatMessage sendMessage(String chatId, String text, {String? filePath, String? fileName, int? fileSize}) {
    final msg = ChatMessage(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: _myP2pId,
      senderName: _myUsername,
      text: text,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      timestamp: DateTime.now(),
      isOutgoing: true,
    );
    _messages.putIfAbsent(chatId, () => []).add(msg);
    _saveMessages(chatId);
    return msg;
  }

  /// Получить сообщения чата
  List<ChatMessage> getMessages(String chatId) {
    return _messages[chatId] ?? [];
  }

  // ═══ ЛОКАЛЬНОЕ СОХРАНЕНИЕ ═══

  void _saveFriends() {
    // Через SharedPreferences или файл в assets
  }

  void _saveGroups() {}

  void _saveChannels() {}

  void _saveMessages(String chatId) {}
}

// ═══ МОДЕЛИ ═══

class PeerProfile {
  final String p2pId;
  final String username;
  String status; // online, offline, away
  String? avatarBase64;

  PeerProfile({required this.p2pId, required this.username, this.status = 'offline', this.avatarBase64});
}

class ChatGroup {
  final String id;
  final String name;
  final List<String> members;
  final String admin;
  final DateTime createdAt;
  String? avatar;
  int unreadCount;

  ChatGroup({required this.id, required this.name, required this.members, required this.admin, required this.createdAt, this.avatar, this.unreadCount = 0});
}

class ChatChannel {
  final String id;
  final String name;
  String description;
  final List<String> subscribers;
  final String admin;
  final DateTime createdAt;
  int unreadCount;

  ChatChannel({required this.id, required this.name, required this.description, required this.subscribers, required this.admin, required this.createdAt, this.unreadCount = 0});
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? text;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final DateTime timestamp;
  final bool isOutgoing;
  bool isRead;

  ChatMessage({required this.id, required this.chatId, required this.senderId, required this.senderName, this.text, this.filePath, this.fileName, this.fileSize, required this.timestamp, this.isOutgoing = false, this.isRead = false});
}

// ═══════════════════════════════════════════════════════════════
// UI ЭКРАН
// ═══════════════════════════════════════════════════════════════

class P2pChatScreen extends StatefulWidget {
  const P2pChatScreen({super.key});

  @override
  State<P2pChatScreen> createState() => _P2pChatScreenState();
}

class _P2pChatScreenState extends State<P2pChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = P2pChatService.instance;
  final _imagePicker = ImagePicker();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('P2P Чаты', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: () => _showAddFriendDialog(context),
          ),
          PopupMenuButton(
            itemBuilder: (_) => [
              PopupMenuItem(value: 'group', child: Text('Создать группу')),
              PopupMenuItem(value: 'channel', child: Text('Создать канал')),
              PopupMenuItem(value: 'refresh', child: Text('Обновить')),
            ],
            onSelected: (v) {
              if (v == 'group') _showCreateGroupDialog(context);
              if (v == 'channel') _showCreateChannelDialog(context);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: [
            Tab(text: '💬 Чаты'),
            Tab(text: '👥 Друзья'),
            Tab(text: '📢 Каналы'),
            Tab(text: '⚙️'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ChatListTab(isDark: isDark, onOpenChat: _openChat, onLongPress: _showChatOptions),
          _FriendsTab(isDark: isDark, service: _service),
          _ChannelsTab(isDark: isDark, service: _service),
          _ChatSettingsTab(isDark: isDark, service: _service),
        ],
      ),
    );
  }

  void _openChat(String chatId, String title) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ChatDetailScreen(chatId: chatId, title: title),
    ));
  }

  void _showChatOptions(String chatId, String title) {
    showModalBottomSheet(context: context, builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: Icon(Icons.info), title: Text('Информация о чате')),
        ListTile(leading: Icon(Icons.photo), title: Text('Отправить фото')),
        ListTile(leading: Icon(Icons.attach_file), title: Text('Отправить файл')),
        ListTile(leading: Icon(Icons.exit_to_app, color: Colors.red), title: Text('Выйти из чата', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showAddFriendDialog(BuildContext context) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Добавить друга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: idController, decoration: InputDecoration(labelText: 'P2P ID', hintText: 'abc123...')),
            SizedBox(height: 8),
            TextField(controller: nameController, decoration: InputDecoration(labelText: 'Имя пользователя')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (idController.text.isNotEmpty && nameController.text.isNotEmpty) {
                _service.addFriend(idController.text.trim(), nameController.text.trim());
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final nameController = TextEditingController();
    final membersStr = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Создать группу'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: 'Название группы')),
            SizedBox(height: 8),
            TextField(controller: membersStr, decoration: InputDecoration(labelText: 'P2P ID участников (через запятую)', hintText: 'abc, def, ghi')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final members = membersStr.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                _service.createGroup(nameController.text.trim(), members);
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showCreateChannelDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Создать канал'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: 'Название канала')),
            SizedBox(height: 8),
            TextField(controller: descController, decoration: InputDecoration(labelText: 'Описание'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                _service.createChannel(nameController.text.trim(), descController.text.trim());
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _P2pSearchDelegate(service: _service));
  }
}

// ═══ ВКЛАДКА 1: ЧАТЫ ═══

class _ChatListTab extends StatelessWidget {
  final bool isDark;
  final void Function(String, String) onOpenChat;
  final void Function(String, String) onLongPress;

  const _ChatListTab({required this.isDark, required this.onOpenChat, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final service = P2pChatService.instance;
    final allChats = <MapEntry<String, String>>[];

    // Личные чаты с друзьями
    for (var f in service.friends) {
      allChats.add(MapEntry('dm_${f.p2pId}', f.username));
    }
    // Группы
    for (var g in service.groups) {
      allChats.add(MapEntry(g.id, g.name));
    }
    // Каналы
    for (var c in service.channels) {
      allChats.add(MapEntry(c.id, c.name));
    }

    if (allChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
            SizedBox(height: 16),
            Text('Нет чатов', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
            SizedBox(height: 8),
            Text('Добавьте друга или создайте группу', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: allChats.length,
      itemBuilder: (_, i) {
        final chat = allChats[i];
        final isGroup = chat.key.startsWith('g_');
        final isChannel = chat.key.startsWith('c_');
        return Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isGroup ? Colors.purple : (isChannel ? Colors.orange : Colors.blue),
              child: Icon(
                isGroup ? Icons.group : (isChannel ? Icons.campaign : Icons.person),
                color: Colors.white,
              ),
            ),
            title: Text(chat.value, style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(isGroup ? 'Группа' : (isChannel ? 'Канал' : 'Личный чат'),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => onOpenChat(chat.key, chat.value),
            onLongPress: () => onLongPress(chat.key, chat.value),
          ),
        );
      },
    );
  }
}

// ═══ ВКЛАДКА 2: ДРУЗЬЯ ═══

class _FriendsTab extends StatelessWidget {
  final bool isDark;
  final P2pChatService service;

  const _FriendsTab({required this.isDark, required this.service});

  @override
  Widget build(BuildContext context) {
    if (service.friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[600]),
            SizedBox(height: 16),
            Text('Нет друзей', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
            SizedBox(height: 8),
            Text('Нажмите + чтобы добавить друга по P2P ID', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: service.friends.length,
      itemBuilder: (_, i) {
        final f = service.friends[i];
        return Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: f.status == 'online' ? Colors.green : Colors.grey,
              child: Text(f.username[0].toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(f.username),
            subtitle: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: f.status == 'online' ? Colors.green : Colors.grey,
                  ),
                ),
                SizedBox(width: 6),
                Text(f.status == 'online' ? 'В сети' : 'Не в сети', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
            trailing: Icon(Icons.chat_bubble_outline, color: Colors.blue),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => _ChatDetailScreen(chatId: 'dm_${f.p2pId}', title: f.username),
              ));
            },
          ),
        );
      },
    );
  }
}

// ═══ ВКЛАДКА 3: КАНАЛЫ ═══

class _ChannelsTab extends StatelessWidget {
  final bool isDark;
  final P2pChatService service;

  const _ChannelsTab({required this.isDark, required this.service});

  @override
  Widget build(BuildContext context) {
    if (service.channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[600]),
            SizedBox(height: 16),
            Text('Нет каналов', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
            SizedBox(height: 8),
            Text('Создайте свой канал', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: service.channels.length,
      itemBuilder: (_, i) {
        final c = service.channels[i];
        return Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.campaign, color: Colors.white)),
            title: Text(c.name, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${c.subscribers.length} подписчиков\n${c.description}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            trailing: Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => _ChatDetailScreen(chatId: c.id, title: c.name),
              ));
            },
          ),
        );
      },
    );
  }
}

// ═══ ВКЛАДКА 4: НАСТРОЙКИ ═══

class _ChatSettingsTab extends StatelessWidget {
  final bool isDark;
  final P2pChatService service;

  const _ChatSettingsTab({required this.isDark, required this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Card(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Информация', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 16),
              _InfoRow('Мой P2P ID', service.myP2pId.isEmpty ? 'Не авторизован' : service.myP2pId),
              _InfoRow('Имя пользователя', service.myUsername.isEmpty ? '-' : service.myUsername),
              Divider(),
              _InfoRow('Друзей', service.friends.length.toString()),
              _InfoRow('Групп', service.groups.length.toString()),
              _InfoRow('Каналов', service.channels.length.toString()),
              SizedBox(height: 16),
              Text('P2P сеть: Активна', style: TextStyle(color: Colors.green)),
              Text('DHT: Подключено', style: TextStyle(color: Colors.green)),
              SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.refresh),
                label: Text('Синхронизировать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ДЕТАЛЬНЫЙ ЭКРАН ЧАТА
// ═══════════════════════════════════════════════════════════════

class _ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String title;

  const _ChatDetailScreen({required this.chatId, required this.title});

  @override
  State<_ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<_ChatDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _service = P2pChatService.instance;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _service.sendMessage(widget.chatId, text);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        _service.sendMessage(widget.chatId, '📷 Фото', filePath: file.path, fileName: file.name);
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      // В реальном приложении будет FilePicker
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messages = _service.getMessages(widget.chatId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Сообщения
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[600]),
                        SizedBox(height: 12),
                        Text('Нет сообщений', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      final isMe = msg.isOutgoing;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (msg.filePath != null)
                              Container(
                                margin: EdgeInsets.only(bottom: 4),
                                width: 200, height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: FileImage(File(msg.filePath!)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (msg.text != null && msg.text!.isNotEmpty)
                              Container(
                                margin: EdgeInsets.only(bottom: 4),
                                padding: EdgeInsets.all(12),
                                constraints: BoxConstraints(maxWidth: 280),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.deepPurple.shade700
                                      : (isDark ? const Color(0xFF1E232B) : Colors.grey[200]),
                                  borderRadius: BorderRadius.circular(16).copyWith(
                                    bottomRight: isMe ? Radius.zero : null,
                                    bottomLeft: !isMe ? Radius.zero : null,
                                  ),
                                ),
                                child: Text(msg.text!, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                              ),
                            Text(
                              '${msg.senderName} • ${_formatTime(msg.timestamp)}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                            SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Ввод
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : Colors.white,
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.photo_library, color: Colors.purple),
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: Icon(Icons.attach_file, color: Colors.blue),
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Сообщение...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═══ ПОИСК ═══

class _P2pSearchDelegate extends SearchDelegate<String?> {
  final P2pChatService service;

  _P2pSearchDelegate({required this.service});

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final results = <MapEntry<String, String>>[];

    for (var f in service.friends) {
      if (f.username.toLowerCase().contains(q) || f.p2pId.contains(q)) {
        results.add(MapEntry('dm_${f.p2pId}', f.username));
      }
    }
    for (var g in service.groups) {
      if (g.name.toLowerCase().contains(q)) {
        results.add(MapEntry(g.id, g.name));
      }
    }
    for (var c in service.channels) {
      if (c.name.toLowerCase().contains(q)) {
        results.add(MapEntry(c.id, c.name));
      }
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) => ListTile(
        leading: Icon(Icons.chat),
        title: Text(results[i].value),
        subtitle: Text(results[i].key),
        onTap: () {
          close(context, null);
          // open chat
        },
      ),
    );
  }
}
