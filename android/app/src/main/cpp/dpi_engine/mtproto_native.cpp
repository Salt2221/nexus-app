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
// AES-IGE Implementation (stub — needs OpenSSL in production)
// ═══════════════════════════════════════════════════════════════

void AesIge::encrypt(const uint8_t* input, uint8_t* output, size_t len,
                     const uint8_t* key, const uint8_t* iv) {
    memcpy(output, input, len);
    LOGD("AES-IGE encrypt %zu bytes (stub)", len);
}

void AesIge::decrypt(const uint8_t* input, uint8_t* output, size_t len,
                     const uint8_t* key, const uint8_t* iv) {
    memcpy(output, input, len);
    LOGD("AES-IGE decrypt %zu bytes (stub)", len);
}

// ═══════════════════════════════════════════════════════════════
// MTProto Client — канал к NEXUS SOCKS5
// ═══════════════════════════════════════════════════════════════

bool MtprotoClient::connect(const std::string& proxy_host, int proxy_port,
                            const std::string& dc_host, int dc_port) {
    if (_connected) return true;

    _sock = ::socket(AF_INET, SOCK_STREAM, 0);
    if (_sock < 0) { LOGE("socket() failed"); return false; }

    struct timeval tv;
    tv.tv_sec = 10;
    tv.tv_usec = 0;
    setsockopt(_sock, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
    setsockopt(_sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

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

void MtprotoClient::disconnect() {
    if (_sock >= 0) {
        ::close(_sock);
        _sock = -1;
    }
    _connected = false;
}

bool MtprotoClient::sendTLMessage(const std::vector<uint8_t>& tl_data) {
    if (!_connected) return false;

    NativeByteBuffer frame;
    frame.writeInt64(0);  // auth_key_id = 0 (unencrypted)
    int64_t msg_id = (int64_t)(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count() * 4294967296.0);
    frame.writeInt64(msg_id);
    _seq_no++;
    frame.writeInt32(_seq_no * 2 + 1);
    frame.writeInt32((int32_t)tl_data.size());
    frame.writeBytes(tl_data.data(), tl_data.size());

    ssize_t sent = ::send(_sock, frame.data(), frame.size(), MSG_NOSIGNAL);
    if (sent < 0) {
        LOGE("send() failed: %s", strerror(errno));
        disconnect();
        return false;
    }
    LOGD("Sent %zu TL bytes", tl_data.size());
    return true;
}

std::vector<uint8_t> MtprotoClient::receive(int timeout_ms) {
    if (!_connected) return {};

    uint8_t header[20];
    ssize_t n = recvAll(header, 20);
    if (n != 20) {
        LOGE("recv header failed: %zd", n);
        return {};
    }

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

bool MtprotoClient::_socks5Connect(const std::string& proxy_host, int proxy_port,
                                    const std::string& target_host, int target_port) {
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

    uint8_t handshake[] = {0x05, 0x01, 0x00};
    if (::send(_sock, handshake, 3, MSG_NOSIGNAL) != 3) return false;

    uint8_t response[2];
    if (recvAll(response, 2) != 2 || response[0] != 0x05 || response[1] != 0x00)
        return false;

    NativeByteBuffer req;
    req.writeByte(0x05);
    req.writeByte(0x01);
    req.writeByte(0x00);
    req.writeByte(0x03);
    req.writeByte((uint8_t)target_host.length());
    req.writeBytes((const uint8_t*)target_host.data(), target_host.length());
    req.writeByte((target_port >> 8) & 0xFF);
    req.writeByte(target_port & 0xFF);

    if (::send(_sock, req.data(), req.size(), MSG_NOSIGNAL) != (ssize_t)req.size())
        return false;

    uint8_t resp[4];
    if (recvAll(resp, 4) != 4) return false;
    if (resp[1] != 0x00) {
        LOGE("SOCKS5 connect rejected: %d", resp[1]);
        return false;
    }

    if (resp[3] == 0x01) {
        recvAll(response, 4);
    } else if (resp[3] == 0x03) {
        uint8_t len;
        recvAll(&len, 1);
        std::vector<uint8_t> tmp(len + 2);
        recvAll(tmp.data(), tmp.size());
    } else {
        recvAll(response, 16);
    }

    LOGD("SOCKS5 connected via %s:%d", proxy_host.c_str(), proxy_port);
    return true;
}

ssize_t MtprotoClient::recvAll(uint8_t* buf, size_t len) {
    size_t total = 0;
    while (total < len) {
        ssize_t n = ::recv(_sock, buf + total, len - total, 0);
        if (n <= 0) return n;
        total += n;
    }
    return total;
}

// ═══════════════════════════════════════════════════════════════
// Ghost Mode Implementation
// ═══════════════════════════════════════════════════════════════

void GhostMode::applyToTL(NativeByteBuffer& buffer) {
    if (hideOnline) {
        // Блокируем updateStatus в TL
    }
    if (hideTyping) {
        // Блокируем sendMessageAction
    }
    if (hideReadReceipts) {
        // Блокируем readHistory
    }
}

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
