// ═══════════════════════════════════════════════════════════════
// NEXUSGram — MTProto Native (как в exteraGram/Nekogram)
//
// Архитектура на основе Telegram для Android:
//   TLRPC (pure C++) → NativeByteBuffer → SerializedData
//   → TCP/HTTP Socket → NEXUS SOCKS5 (127.0.0.1:1443)
//
// Без TDLib. Прямое TL-сериализованное сообщение по MTProto 2.0.
// ═══════════════════════════════════════════════════════════════

#include "mtproto_native.h"
#include <android/log.h>
#include <cstring>
#include <sstream>
#include <random>
#include <chrono>
#include <thread>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <zlib.h>

#define LOG_TAG "NexusMTProto"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ═══════════════════════════════════════════════════════════════
// TL Serialization — как в Telegram для Android
// ═══════════════════════════════════════════════════════════════

class NativeByteBuffer {
public:
    NativeByteBuffer() : _pos(0) {}
    NativeByteBuffer(const std::vector<uint8_t>& data) : _data(data), _pos(0) {}

    void writeInt32(int32_t v) {
        v = htonl(v);
        append((uint8_t*)&v, 4);
    }

    void writeInt64(int64_t v) {
        uint32_t low = (uint32_t)(v & 0xFFFFFFFF);
        uint32_t high = (uint32_t)((v >> 32) & 0xFFFFFFFF);
        writeInt32(low);
        writeInt32(high);
    }

    void writeDouble(double v) {
        uint64_t bits;
        memcpy(&bits, &v, 8);
        writeInt64(bits);
    }

    void writeBytes(const uint8_t* data, size_t len) {
        append(data, len);
    }

    void writeString(const std::string& s) {
        size_t len = s.length();
        // serialization: bytes with length prefix
        if (len < 254) {
            writeByte((uint8_t)len);
            writeBytes((const uint8_t*)s.data(), len);
            // padding to 4 bytes
            size_t pad = (len + 1) % 4;
            if (pad > 0) {
                for (size_t i = 0; i < 4 - pad; i++) writeByte(0);
            }
        } else {
            writeByte(254);
            writeByte((uint8_t)(len & 0xFF));
            writeByte((uint8_t)((len >> 8) & 0xFF));
            writeByte((uint8_t)((len >> 16) & 0xFF));
            writeBytes((const uint8_t*)s.data(), len);
            size_t pad = len % 4;
            if (pad > 0) {
                for (size_t i = 0; i < 4 - pad; i++) writeByte(0);
            }
        }
    }

    void writeByte(uint8_t b) {
        _data.push_back(b);
    }

    void writeBool(bool v) {
        // boolTrue = 0x997275b5, boolFalse = 0xbc799737
        writeInt32(v ? 0x997275b5 : 0xbc799737);
    }

    void writeInt32Vector(const std::vector<int32_t>& vec) {
        writeInt32(0x1cb5c415); // vector constructor
        writeInt32((int32_t)vec.size());
        for (auto v : vec) writeInt32(v);
    }

    int32_t readInt32() {
        if (_pos + 4 > _data.size()) return 0;
        int32_t v;
        memcpy(&v, &_data[_pos], 4);
        _pos += 4;
        return ntohl(v);
    }

    int64_t readInt64() {
        uint32_t low = (uint32_t)readInt32();
        uint32_t high = (uint32_t)readInt32();
        return ((int64_t)high << 32) | low;
    }

    void readBytes(uint8_t* out, size_t len) {
        if (_pos + len > _data.size()) return;
        memcpy(out, &_data[_pos], len);
        _pos += len;
    }

    std::string readString() {
        if (_pos >= _data.size()) return "";
        size_t len;
        if (_data[_pos] < 254) {
            len = _data[_pos];
            _pos++;
        } else {
            len = (size_t)_data[_pos + 1] | ((size_t)_data[_pos + 2] << 8) | ((size_t)_data[_pos + 3] << 16);
            _pos += 4;
        }
        if (_pos + len > _data.size()) return "";
        std::string s((const char*)&_data[_pos], len);
        _pos += len;
        return s;
    }

    size_t position() const { return _pos; }
    size_t remaining() const { return _data.size() - _pos; }
    const uint8_t* data() const { return _data.data(); }
    size_t size() const { return _data.size(); }
    std::vector<uint8_t> getData() const { return _data; }

    void append(const uint8_t* d, size_t len) {
        _data.insert(_data.end(), d, d + len);
    }

private:
    std::vector<uint8_t> _data;
    size_t _pos;
};

// ═══════════════════════════════════════════════════════════════
// AES-IGE for MTProto 2.0
// ═══════════════════════════════════════════════════════════════

// Simplified AES-IGE implementation (full implementation needs openssl)
// В продакшене используем OpenSSL EVP_aes_256_ige()

class AesIge {
public:
    static void encrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv) {
        // Simplified — in production use OpenSSL
        // Здесь должна быть полная реализация AES-256-IGE
        memcpy(output, input, len);
        LOGD("AES-IGE encrypt %zu bytes (stub)", len);
    }

    static void decrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv) {
        memcpy(output, input, len);
        LOGD("AES-IGE decrypt %zu bytes (stub)", len);
    }
};

// ═══════════════════════════════════════════════════════════════
// MTProto Client — канал к прокси/NEXUS
// ═══════════════════════════════════════════════════════════════

class MtprotoClient {
public:
    MtprotoClient() : _sock(-1), _seq_no(0), _connected(false), _dc_id(2) {}

    ~MtprotoClient() {
        disconnect();
    }

    // ─── Подключение через NEXUS SOCKS5 ───

    bool connect(const std::string& proxy_host, int proxy_port,
                 const std::string& dc_host, int dc_port) {
        if (_connected) return true;

        _sock = ::socket(AF_INET, SOCK_STREAM, 0);
        if (_sock < 0) { LOGE("socket() failed"); return false; }

        // Timeout
        struct timeval tv;
        tv.tv_sec = 10;
        tv.tv_usec = 0;
        setsockopt(_sock, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
        setsockopt(_sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

        // TCP_NODELAY
        int flag = 1;
        setsockopt(_sock, IPPROTO_TCP, TCP_NODELAY, (const char*)&flag, sizeof(flag));

        // SOCKS5 handshake через NEXUS
        if (!_socks5Connect(proxy_host, proxy_port, dc_host, dc_port)) {
            LOGE("SOCKS5 connection failed");
            ::close(_sock);
            _sock = -1;
            return false;
        }

        _dc_host = dc_host;
        _dc_port = dc_port;
        _connected = true;
        _seq_no = 0;

        LOGD("MTProto connected via %s:%d -> DC %s:%d",
             proxy_host.c_str(), proxy_port, dc_host.c_str(), dc_port);
        return true;
    }

    void disconnect() {
        if (_sock >= 0) {
            ::close(_sock);
            _sock = -1;
        }
        _connected = false;
    }

    // ─── Отправка TL-сообщения ───

    bool sendTLMessage(const std::vector<uint8_t>& tl_data) {
        if (!_connected) return false;

        // MTProto 2.0 frame: auth_key_id (8) + msg_id (8) + msg_len (4) + seq_no (4) + salt (8?)
        // + session_id (8) + body_len (4) + body (N) + padding

        NativeByteBuffer frame;

        // auth_key_id = 0 (unencrypted)
        frame.writeInt64(0);
        // msg_id = timestamp << 32
        int64_t msg_id = (int64_t)(std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count() * 4294967296.0);
        frame.writeInt64(msg_id);
        // seq_no
        _seq_no++;
        frame.writeInt32(_seq_no * 2 + 1);
        // body length
        frame.writeInt32((int32_t)tl_data.size());
        // body
        frame.writeBytes(tl_data.data(), tl_data.size());

        // send raw bytes
        ssize_t sent = ::send(_sock, frame.data(), frame.size(), MSG_NOSIGNAL);
        if (sent < 0) {
            LOGE("send() failed: %s", strerror(errno));
            disconnect();
            return false;
        }

        LOGD("Sent %zu TL bytes", tl_data.size());
        return true;
    }

    // ─── Получение ответа ───

    std::vector<uint8_t> receive(int timeout_ms = 10000) {
        if (!_connected) return {};

        uint8_t header[20];
        ssize_t n = recvAll(header, 20);
        if (n != 20) {
            LOGE("recv header failed: %zd", n);
            return {};
        }

        // Parse header
        NativeByteBuffer hdr(header, 20);
        int64_t auth_key_id = hdr.readInt64();
        int64_t msg_id = hdr.readInt64();
        int32_t msg_len = hdr.readInt32();

        if (msg_len <= 0 || msg_len > 1024 * 1024) {
            LOGE("invalid msg_len: %d", msg_len);
            return {};
        }

        std::vector<uint8_t> body(msg_len);
        n = recvAll(body.data(), msg_len);
        if (n != msg_len) {
            LOGE("recv body failed: %zd/%d", n, msg_len);
            return {};
        }

        LOGD("Received %d TL bytes (auth_key=%lld, msg_id=%lld)",
             msg_len, (long long)auth_key_id, (long long)msg_id);
        return body;
    }

    bool isConnected() const { return _connected; }

private:
    int _sock;
    int _seq_no;
    bool _connected;
    std::string _dc_host;
    int _dc_port;
    int _dc_id;

    bool _socks5Connect(const std::string& proxy_host, int proxy_port,
                        const std::string& target_host, int target_port) {
        // Resolve proxy
        struct hostent* he = gethostbyname(proxy_host.c_str());
        if (!he) return false;

        struct sockaddr_in addr;
        addr.sin_family = AF_INET;
        addr.sin_port = htons(proxy_port);
        memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);

        if (::connect(_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            LOGE("proxy connect failed: %s", strerror(errno));
            return false;
        }

        // SOCKS5 handshake
        // Version 5, 1 auth method: no auth
        uint8_t handshake[] = {0x05, 0x01, 0x00};
        if (::send(_sock, handshake, 3, MSG_NOSIGNAL) != 3) return false;

        uint8_t response[2];
        if (recvAll(response, 2) != 2 || response[0] != 0x05 || response[1] != 0x00)
            return false;

        // SOCKS5 connect request
        NativeByteBuffer req;
        req.writeByte(0x05); // version
        req.writeByte(0x01); // connect
        req.writeByte(0x00); // reserved
        req.writeByte(0x03); // domain name

        req.writeByte((uint8_t)target_host.length());
        req.writeBytes((const uint8_t*)target_host.data(), target_host.length());
        req.writeByte((target_port >> 8) & 0xFF);
        req.writeByte(target_port & 0xFF);

        if (::send(_sock, req.data(), req.size(), MSG_NOSIGNAL) != (ssize_t)req.size())
            return false;

        // Read response
        uint8_t resp[4];
        if (recvAll(resp, 4) != 4) return false;
        if (resp[1] != 0x00) { // success
            LOGE("SOCKS5 connect rejected: %d", resp[1]);
            return false;
        }

        // read remaining (bound addr + port)
        if (resp[3] == 0x01) {
            recvAll(response, 4); // IPv4 + 2 port
        } else if (resp[3] == 0x03) {
            uint8_t len;
            recvAll(&len, 1);
            std::vector<uint8_t> tmp(len + 2);
            recvAll(tmp.data(), tmp.size());
        } else {
            recvAll(response, 16); // IPv6 + 2 port
        }

        LOGD("SOCKS5 connected via %s:%d", proxy_host.c_str(), proxy_port);
        return true;
    }

    ssize_t recvAll(uint8_t* buf, size_t len) {
        size_t total = 0;
        while (total < len) {
            ssize_t n = ::recv(_sock, buf + total, len - total, 0);
            if (n <= 0) return n;
            total += n;
        }
        return total;
    }
};

// ═══════════════════════════════════════════════════════════════
// TON IC для хранения ключей — как в AyuGram
// ═══════════════════════════════════════════════════════════════

// Демо-реализация TON IC для хранения P2P ключей
// В продакшене — настоящий TON Smart Contract

// ═══════════════════════════════════════════════════════════════
// Ghost Mode — скрытие активности (как в AyuGram)
// ═══════════════════════════════════════════════════════════════

class GhostMode {
public:
    bool enabled = false;
    bool hideTyping = true;
    bool hideOnline = true;
    bool hideReadReceipts = true;
    bool antiRecall = true;  // AyuGram feature
    bool localPremium = false; // Local Telegram Premium

    // Отключаем отправку typing/online status в TL-сообщениях
    void applyToTL(NativeByteBuffer& buffer) {
        // В продакшене: модификация TL-сообщений перед отправкой
        if (hideOnline) {
            // Удаляем updateStatus из очереди
        }
        if (hideTyping) {
            // Блокируем sendMessageAction
        }
        if (hideReadReceipts) {
            // Блокируем readHistory
        }
    }
};

// ═══════════════════════════════════════════════════════════════
// NEXUS API ID — регистрация через NEXUS, а не Telegram
// ═══════════════════════════════════════════════════════════════

// Используем API ID и Hash из NEXUS конфига,
// а не стандартный 2040

// ═══════════════════════════════════════════════════════════════
// JNI Bridge
// ═══════════════════════════════════════════════════════════════

#include <jni.h>

static MtprotoClient* g_client = nullptr;
static GhostMode g_ghost;

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeMtprotoConnect(
    JNIEnv* env, jobject thiz,
    jstring proxy_host, jint proxy_port,
    jstring dc_host, jint dc_port) {

    const char* ph = env->GetStringUTFChars(proxy_host, nullptr);
    const char* dh = env->GetStringUTFChars(dc_host, nullptr);

    if (!g_client) g_client = new MtprotoClient();
    bool ok = g_client->connect(ph, proxy_port, dh, dc_port);

    env->ReleaseStringUTFChars(proxy_host, ph);
    env->ReleaseStringUTFChars(dc_host, dh);

    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeMtprotoSetGhost(
    JNIEnv* env, jobject thiz,
    jboolean enable, jboolean hide_typing,
    jboolean hide_online, jboolean antirecall) {

    g_ghost.enabled = enable;
    g_ghost.hideTyping = hide_typing;
    g_ghost.hideOnline = hide_online;
    g_ghost.antiRecall = antirecall;

    LOGD("Ghost mode: enabled=%d, typing=%d, online=%d, recall=%d",
         enable, hide_typing, hide_online, antirecall);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeMtprotoDisconnect(JNIEnv* env, jobject thiz) {
    if (g_client) {
        g_client->disconnect();
        delete g_client;
        g_client = nullptr;
    }
}
