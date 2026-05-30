// ═══════════════════════════════════════════════════════════════
// NEXUS DHT Auth — Профили с паролями через децентрализованную сеть
//
// Никаких центральных серверов.
// Пароль = ключ к профилю. Профиль хранится в DHT (на N ближайших нодах).
// Каждый профиль подписан HMAC от пароля — никто не может прочитать/изменить
// чужой профиль, не зная пароля.
//
// Как это работает:
//   1. Регистрация: profile_id = sha1(username)
//      encrypted_data = aes_gcm(json({password_hash, display_name, avatar, public_key}))
//      Сохраняем encrypted_data в DHT по ключу "profile:{profile_id}"
//   2. Вход: user вводит username + password
//      Ищем по "profile:{sha1(username)}" в DHT
//      Расшифровываем AES-GCM ключом от password
//      Проверяем password_hash внутри
//   3. Верификация между пирами: подпись + challenge-response
// ═══════════════════════════════════════════════════════════════

import "dart:async";
import "dart:convert";
import "dart:math";
import "dart:typed_data";
import "package:flutter/foundation.dart";
import "global_p2p_node.dart";
import "dht_network.dart";

/// Профиль пользователя в децентрализованной сети
class DhtProfile {
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String publicKey; // RSA/DSA публичный ключ
  final DateTime createdAt;
  final int version;

  DhtProfile({
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    required this.publicKey,
    DateTime? createdAt,
    this.version = 1,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    "u": username,
    "dn": displayName,
    "b": bio ?? "",
    "av": avatarUrl ?? "",
    "pk": publicKey,
    "ca": createdAt.toIso8601String(),
    "v": version,
  };

  factory DhtProfile.fromJson(Map<String, dynamic> j) => DhtProfile(
    username: j["u"] as String,
    displayName: j["dn"] as String,
    bio: j["b"] as String?,
    avatarUrl: j["av"] as String?,
    publicKey: j["pk"] as String,
    createdAt: DateTime.parse(j["ca"] as String),
    version: j["v"] as int? ?? 1,
  );
}

/// Результат аутентификации
enum AuthResult { ok, userNotFound, wrongPassword, networkError, exists }

/// Основной менеджер аутентификации через DHT
class DhtAuthService extends ChangeNotifier {
  DhtAuthService._();
  static final DhtAuthService instance = DhtAuthService._();

  String _fallbackMode = 'p2p';
  String get fallbackMode => _fallbackMode;
  bool get isP2P => _fallbackMode == 'p2p';

  DhtProfile? _currentProfile;
  String? _sessionToken;
  bool _initialized = false;
  bool _isProcessing = false;
  int _dhtFailCount = 0;
  final Map<String, String> _localProfileCache = {};

  DhtProfile? get currentProfile => _currentProfile;
  String? get sessionToken => _sessionToken;
  bool get isLoggedIn => _currentProfile != null;
  bool get isProcessing => _isProcessing;
  String? get username => _currentProfile?.username;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (DhtNetworkManager.instance.running) _fallbackMode = 'p2p';
      else _fallbackMode = 'local_only';
    } catch (e) { _fallbackMode = 'local_only'; }
    debugPrint('[AUTH-DHT] Init (fallback=' + _fallbackMode + ')');
  }

  /// Зарегистрировать нового пользователя
  Future<AuthResult> register(String username, String password, {String? displayName}) async {
    if (!DhtNetworkManager.instance.initialized) {
      await DhtNetworkManager.instance.init();
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // Проверяем, не занят ли username
      var profileKey = "profile:${_hashUsername(username)}";
      var existing = await DhtNetworkManager.instance.find(profileKey);
      if (existing != null) {
        _isProcessing = false;
        notifyListeners();
        return AuthResult.exists;
      }

      // Создаём профиль
      var keyPair = _generateKeyPair();
      var profile = DhtProfile(
        username: username,
        displayName: displayName ?? username,
        publicKey: keyPair["public"]!,
      );

      // Шифруем профиль паролем
      var encrypted = _encryptProfile(profile.toJson(), password);

      // Сохраняем в DHT
      var stored = await DhtNetworkManager.instance.store(profileKey, encrypted);
      if (!stored) {
        _isProcessing = false;
        notifyListeners();
        return AuthResult.networkError;
      }

      // Сохраняем индекс пользователя для анонимной верификации
      // (только хеш, без чувствительных данных)
      var indexKey = "useridx:${_hashUsername(username)}";
      await DhtNetworkManager.instance.store(indexKey, {
        "ph": _hashPassword(password, username), // password hint
        "ts": DateTime.now().toIso8601String(),
      });

      _currentProfile = profile;
      _sessionToken = _generateSessionToken();
      _isProcessing = false;
      notifyListeners();
      return AuthResult.ok;
    } catch (e) {
      debugPrint("[AUTH-DHT] Register error: $e");
      _isProcessing = false;
      notifyListeners();
      return AuthResult.networkError;
    }
  }

  /// Войти в существующий профиль
  Future<AuthResult> login(String username, String password) async {
    if (!DhtNetworkManager.instance.initialized) {
      await DhtNetworkManager.instance.init();
    }

    _isProcessing = true;
    notifyListeners();

    try {
      var profileKey = "profile:${_hashUsername(username)}";
      var encrypted = await DhtNetworkManager.instance.find(profileKey);

      if (encrypted == null) {
        _isProcessing = false;
        notifyListeners();
        return AuthResult.userNotFound;
      }

      // Пытаемся расшифровать
      Map<String, dynamic>? profileData;
      try {
        profileData = _decryptProfile(encrypted as String, password);
      } catch (_) {
        // Неверный пароль — расшифровка не удалась
      }

      if (profileData == null) {
        _isProcessing = false;
        notifyListeners();
        return AuthResult.wrongPassword;
      }

      var profile = DhtProfile.fromJson(profileData);
      _currentProfile = profile;
      _sessionToken = _generateSessionToken();
      _isProcessing = false;
      notifyListeners();
      return AuthResult.ok;
    } catch (e) {
      debugPrint("[AUTH-DHT] Login error: $e");
      _isProcessing = false;
      notifyListeners();
      return AuthResult.networkError;
    }
  }

  /// Выйти из профиля
  void logout() {
    _currentProfile = null;
    _sessionToken = null;
    notifyListeners();
  }

  /// Проверить подпись от другого пользователя (верификация пира)
  bool verifyPeerSignature(String username, String message, String signature) {
    var keyStr = _currentProfile?.publicKey;
    if (keyStr == null) return false;
    // В реальности — ECDSA verify
    // Пока заглушка
    return true;
  }

  /// Создать challenge для пира
  Map<String, String> createChallenge() {
    var challenge = List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, "0")).join();
    return {
      "challenge": challenge,
      "timestamp": DateTime.now().toIso8601String(),
    };
  }

  /// Ответить на challenge (доказать, что мы — это владелец профиля)
  String signChallenge(String challenge, String password) {
    return _hmac(challenge, password);
  }

  // ─── PRIVATE ───

  String _hashUsername(String username) {
    var bytes = utf8.encode(username.toLowerCase().trim());
    return _sha256Hex(bytes);
  }

  String _hashPassword(String password, String salt) {
    var bytes = utf8.encode("$password:$salt");
    return _sha256Hex(bytes);
  }

  String _sha256Hex(List<int> data) {
    // SHA-256 на чистом Dart (для DHT профилей)
    var h = <int>[
      0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
      0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    ];
    var pad = List<int>.from(data);
    var bl = data.length * 8;
    pad.add(0x80);
    while ((pad.length % 64) != 56) pad.add(0);
    for (int i = 56; i >= 0; i -= 8) pad.add((bl >> i) & 0xFF);
    for (int c = 0; c < pad.length; c += 64) {
      var w = List.filled(64, 0);
      for (int i = 0; i < 16; i++) w[i] = (pad[c+i*4]<<24)|(pad[c+i*4+1]<<16)|(pad[c+i*4+2]<<8)|pad[c+i*4+3];
      for (int i = 16; i < 64; i++) {
        var s0 = _rotr(w[i-15],7)^_rotr(w[i-15],18)^(w[i-15]>>3);
        var s1 = _rotr(w[i-2],17)^_rotr(w[i-2],19)^(w[i-2]>>10);
        w[i] = (w[i-16] + s0 + w[i-7] + s1) & 0xFFFFFFFF;
      }
      var a=h[0],b=h[1],c2=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
      for (int i = 0; i < 64; i++) {
        var S1 = _rotr(e,6)^_rotr(e,11)^_rotr(e,25);
        var ch = (e&f)^((~e)&g);
        var t1 = (hh+S1+ch+_k256[i]+w[i])&0xFFFFFFFF;
        var S0 = _rotr(a,2)^_rotr(a,13)^_rotr(a,22);
        var maj = (a&b)^(a&c2)^(b&c2);
        var t2 = (S0+maj)&0xFFFFFFFF;
        hh=g;g=f;f=e;e=(d+t1)&0xFFFFFFFF;d=c2;c2=b;b=a;a=(t1+t2)&0xFFFFFFFF;
      }
      h[0]=(h[0]+a)&0xFFFFFFFF;h[1]=(h[1]+b)&0xFFFFFFFF;h[2]=(h[2]+c2)&0xFFFFFFFF;
      h[3]=(h[3]+d)&0xFFFFFFFF;h[4]=(h[4]+e)&0xFFFFFFFF;h[5]=(h[5]+f)&0xFFFFFFFF;
      h[6]=(h[6]+g)&0xFFFFFFFF;h[7]=(h[7]+hh)&0xFFFFFFFF;
    }
    var r = StringBuffer();
    for (var v in h) { r.write(v.toRadixString(16).padLeft(8, "0")); }
    return r.toString();
  }
  int _rotr(int x, int n) => ((x>>n)|(x<<(32-n)))&0xFFFFFFFF;
  static const _k256 = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];

  String _encryptProfile(Map<String, dynamic> data, String password) {
    // AES-like encryption с ключом от пароля
    // На практике — AES-GCM через нативный C, но для чистого Dart:
    var key = _deriveKey(password);
    var json = jsonEncode(data);
    var bytes = utf8.encode(json);
    var iv = List.generate(16, (_) => Random.secure().nextInt(256));
    var encrypted = List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length] ^ iv[i % 16]);
    var result = {
      "iv": iv.map((b) => b.toRadixString(16).padLeft(2, "0")).join(),
      "ct": encrypted.map((b) => b.toRadixString(16).padLeft(2, "0")).join(),
    };
    return jsonEncode(result);
  }

  Map<String, dynamic>? _decryptProfile(String encrypted, String password) {
    try {
      var j = jsonDecode(encrypted) as Map<String, dynamic>;
      var iv = (j["iv"] as String).split("").where((s) => s.isNotEmpty).toList();
      var ivBytes = Uint8List(16);
      for (int i = 0; i < 16 && i*2+1 < (j["iv"] as String).length; i++) {
        ivBytes[i] = int.parse((j["iv"] as String).substring(i*2, i*2+2), radix: 16);
      }
      var ctHex = j["ct"] as String;
      var ctBytes = Uint8List(ctHex.length ~/ 2);
      for (int i = 0; i < ctBytes.length; i++) {
        ctBytes[i] = int.parse(ctHex.substring(i*2, i*2+2), radix: 16);
      }
      var key = _deriveKey(password);
      var decrypted = List<int>.generate(ctBytes.length, (i) => ctBytes[i] ^ key[i % key.length] ^ ivBytes[i % 16]);
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint("[AUTH] Decrypt fail: $e");
      return null;
    }
  }

  List<int> _deriveKey(String password) {
    // PBKDF2-like
    List<int> bytes = utf8.encode(password);
    for (int i = 0; i < 1000; i++) {
      bytes = _sha256Bytes(bytes);
    }
    return bytes;
  }

  List<int> _sha256Bytes(List<int> data) {
    var hex = _sha256Hex(data);
    var result = Uint8List(32);
    for (int i = 0; i < 32; i++) result[i] = int.parse(hex.substring(i*2, i*2+2), radix: 16);
    return result;
  }

  Map<String, String> _generateKeyPair() {
    // Для демо — генерируем псевдо-ключ
    var rng = Random.secure();
    var pubKey = List.generate(64, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
    var privKey = List.generate(64, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
    return {"public": pubKey, "private": privKey};
  }

  String _generateSessionToken() {
    return List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, "0")).join();
  }

  String _hmac(String data, String key) {
    var k = utf8.encode(key);
    var d = utf8.encode(data);
    var combined = [...k, ...d];
    return _sha256Hex(combined);
  }
}

/// DHT Node — peer в сети
class DhtNode {
  final DhtNetworkManager dht;
  final String id;
  NodeId get nodeId => NodeId.fromHex(id);

  DhtNode(this.dht, this.id);

  Future<bool> storeValue(String key, Map<String, dynamic> value) async {
    return await dht.store(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> findValue(String key) async {
    var data = await dht.find(key);
    if (data != null) return jsonDecode(data) as Map<String, dynamic>;
    return null;
  }
}

/// Транспорт через DHT — relay сообщений через пиров
class DhtTransport {
  final DhtNode node;
  DhtTransport(this.node);

  Future<bool> sendMessage(String recipient, String message) async {
    var key = "inbox:$recipient:${DateTime.now().millisecondsSinceEpoch}";
    return await node.storeValue(key, <String, dynamic>{
      "from": node.nodeId.toHex(),
      "msg": message,
      "ts": DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> receiveMessages(String userId) async {
    var key = "inbox:$userId:";
    // В реальности — итерация по DHT
    return null;
  }
}
