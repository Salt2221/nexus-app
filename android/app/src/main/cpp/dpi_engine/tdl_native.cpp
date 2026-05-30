// ═══════════════════════════════════════════════════════════════
// TDLib Native Wrapper — MTProto Native через TDLib с C++
// ═══════════════════════════════════════════════════════════════

#include <td/telegram/td_json_client.h>
#include <td/telegram/td_log.h>
#include <cstring>
#include <string>
#include <thread>
#include <atomic>
#include <functional>
#include <android/log.h>

#define LOG_TAG "TdNative"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ═══════════════════════════════════════════════════════════════
// Proxy Config — подключение через NEXUS SOCKS5
// ═══════════════════════════════════════════════════════════════

struct ProxyConfig {
    std::string type = "socks5";   // socks5 | mtproto
    std::string server = "127.0.0.1";
    int port = 1443;
    std::string username;          // опционально
    std::string password;          // опционально
};

// ═══════════════════════════════════════════════════════════════
// TDLib Client — полноценный MTProto Native клиент
// ═══════════════════════════════════════════════════════════════

class TdNativeClient {
public:
    TdNativeClient()
        : client_(nullptr), running_(false), auth_state_(0),
          api_id_(0), proxy_(ProxyConfig()) {}

    ~TdNativeClient() {
        stop();
    }

    // ─── Инициализация с прокси ───

    bool init(int api_id, const std::string& api_hash, const ProxyConfig& proxy) {
        if (client_) return false;

        api_id_ = api_id;
        api_hash_ = api_hash;
        proxy_ = proxy;

        // Включаем логи TDLib
        td_set_log_verbosity_level(2);
        td_set_log_file_path("/data/data/com.nexus.v2/files/tdlib.log");

        // Создаём TDLib клиент
        client_ = td_json_client_create();
        if (!client_) {
            LOGE("Failed to create TDLib client");
            return false;
        }

        running_ = true;
        update_thread_ = std::thread(&TdNativeClient::updateLoop, this);

        // Отправляем конфиг
        sendSetTdlibParameters(api_id_, api_hash_);

        // Устанавливаем прокси через NEXUS
        if (!proxy_.server.empty()) {
            addProxy();
        }

        LOGD("TDLib initialized (API ID: %d, proxy: %s:%d)",
             api_id_, proxy_.server.c_str(), proxy_.port);
        return true;
    }

    void stop() {
        running_ = false;
        if (update_thread_.joinable()) update_thread_.join();
        if (client_) {
            td_json_client_destroy(client_);
            client_ = nullptr;
        }
        LOGD("TDLib stopped");
    }

    // ─── Авторизация ───

    void sendPhoneNumber(const std::string& phone) {
        sendJson(R"({"@type":"setAuthenticationPhoneNumber","phone_number":")" + phone + R"(","settings":{"allow_flash_call":false,"current_number":true}})");
    }

    void sendCode(const std::string& code) {
        sendJson(R"({"@type":"checkAuthenticationCode","code":")" + code + R"("})");
    }

    void sendPassword(const std::string& pwd) {
        sendJson(R"({"@type":"checkAuthenticationPassword","password":")" + pwd + R"("})");
    }

    // ─── Чаты ───

    void getChats() {
        sendJson(R"({"@type":"getChats","offset_order":"9223372036854775807","offset_chat_id":0,"limit":100})");
    }

    void getChatHistory(int64_t chat_id, int64_t from_msg_id = 0, int limit = 50) {
        char buf[512];
        snprintf(buf, sizeof(buf),
                 R"({"@type":"getChatHistory","chat_id":%lld,"from_message_id":%lld,"offset":0,"limit":%d,"only_local":false})",
                 (long long)chat_id, (long long)from_msg_id, limit);
        sendJson(buf);
    }

    void sendMessage(int64_t chat_id, const std::string& text) {
        char buf[1024];
        // Экранируем кавычки в тексте
        std::string safe_text = text;
        size_t pos = 0;
        while ((pos = safe_text.find('"', pos)) != std::string::npos) {
            safe_text.replace(pos, 1, "\\\"");
            pos += 2;
        }

        snprintf(buf, sizeof(buf),
                 R"({"@type":"sendMessage","chat_id":%lld,"input_message_content":{"@type":"inputMessageText","text":{"@type":"formattedText","text":"%s"}}})",
                 (long long)chat_id, safe_text.c_str());
        sendJson(buf);
    }

    // ─── Прокси (NEXUS SOCKS5/MTProto) ───

    void addProxy() {
        if (proxy_.type == "socks5") {
            char buf[512];
            snprintf(buf, sizeof(buf),
                     R"({"@type":"addProxy","server":"%s","port":%d,"enable":true,"type":{"@type":"proxyTypeSocks5","username":"%s","password":"%s"}})",
                     proxy_.server.c_str(), proxy_.port,
                     proxy_.username.c_str(), proxy_.password.c_str());
            sendJson(buf);
            LOGD("Added SOCKS5 proxy: %s:%d", proxy_.server.c_str(), proxy_.port);
        } else if (proxy_.type == "mtproto") {
            char buf[512];
            snprintf(buf, sizeof(buf),
                     R"({"@type":"addProxy","server":"%s","port":%d,"enable":true,"type":{"@type":"proxyTypeMtproto","secret":"%s"}})",
                     proxy_.server.c_str(), proxy_.port, proxy_.password.c_str());
            sendJson(buf);
            LOGD("Added MTProto proxy: %s:%d", proxy_.server.c_str(), proxy_.port);
        }
    }

    void enableProxy() {
        sendJson(R"({"@type":"enableProxy"})");
    }

    void disableProxy() {
        sendJson(R"({"@type":"disableProxy"})");
    }

    // ─── Прочее ───

    int authState() const { return auth_state_; }

    void setUpdateCallback(std::function<void(const std::string&)> cb) {
        update_cb_ = cb;
    }

private:
    void* client_;
    std::atomic<bool> running_;
    std::atomic<int> auth_state_;  // 0=none, 1=code, 2=pwd, 3=ok
    std::thread update_thread_;
    std::function<void(const std::string&)> update_cb_;

    int api_id_;
    std::string api_hash_;
    ProxyConfig proxy_;

    void sendJson(const std::string& json) {
        if (client_) {
            td_json_client_send(client_, json.c_str());
            LOGD("Send: %s", json.substr(0, 80).c_str());
        }
    }

    void sendSetTdlibParameters(int api_id, const std::string& api_hash) {
        char buf[1024];
        snprintf(buf, sizeof(buf),
                 R"({"@type":"setTdlibParameters","use_test_dc":false,)"
                 R"("database_directory":"/data/data/com.nexus.v2/files/tdlib",)"
                 R"("files_directory":"/data/data/com.nexus.v2/files/tdlib/files",)"
                 R"("use_file_database":true,)"
                 R"("use_chat_info_database":true,)"
                 R"("use_message_database":true,)"
                 R"("use_secret_chats":false,)"
                 R"("api_id":%d,)"
                 R"("api_hash":"%s",)"
                 R"("system_language_code":"ru",)"
                 R"("device_model":"Nexus Android",)"
                 R"("system_version":"Android 14",)"
                 R"("application_version":"1.0.8")"
                 R"(})",
                 api_id, api_hash.c_str());
        sendJson(buf);
    }

    void updateLoop() {
        while (running_ && client_) {
            const char* update = td_json_client_receive(client_, 1.0);
            if (update) {
                std::string updateStr(update);
                if (update_cb_) update_cb_(updateStr);

                // Парсим состояние авторизации
                if (updateStr.find("\"@type\":\"updateAuthorizationState\"") != std::string::npos) {
                    if (updateStr.find("authorizationStateWaitCode") != std::string::npos) {
                        auth_state_ = 1;
                    } else if (updateStr.find("authorizationStateWaitPassword") != std::string::npos) {
                        auth_state_ = 2;
                    } else if (updateStr.find("authorizationStateReady") != std::string::npos) {
                        auth_state_ = 3;
                        LOGD("TDLib: authorization OK!");
                    }
                }

                LOGD("Update: %s", updateStr.substr(0, 120).c_str());
            }
        }
    }
};

// ═══════════════════════════════════════════════════════════════
// JNI Bridge — вызывается из DpiNative.kt
// ═══════════════════════════════════════════════════════════════

#include <jni.h>

static TdNativeClient* g_client = nullptr;

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeTdInit(
    JNIEnv* env, jobject thiz,
    jint api_id, jstring api_hash,
    jstring proxy_host, jint proxy_port) {

    const char* hash = env->GetStringUTFChars(api_hash, nullptr);
    const char* host = env->GetStringUTFChars(proxy_host, nullptr);

    if (!g_client) g_client = new TdNativeClient();

    ProxyConfig proxy;
    proxy.server = host;
    proxy.port = proxy_port;

    bool ok = g_client->init(api_id, hash, proxy);

    env->ReleaseStringUTFChars(api_hash, hash);
    env->ReleaseStringUTFChars(proxy_host, host);

    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeTdSendPhone(JNIEnv* env, jobject thiz, jstring phone) {
    if (!g_client) return;
    const char* p = env->GetStringUTFChars(phone, nullptr);
    g_client->sendPhoneNumber(p);
    env->ReleaseStringUTFChars(phone, p);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeTdSendCode(JNIEnv* env, jobject thiz, jstring code) {
    if (!g_client) return;
    const char* c = env->GetStringUTFChars(code, nullptr);
    g_client->sendCode(c);
    env->ReleaseStringUTFChars(code, c);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeTdSendMessage(
    JNIEnv* env, jobject thiz, jlong chat_id, jstring text) {
    if (!g_client) return;
    const char* t = env->GetStringUTFChars(text, nullptr);
    g_client->sendMessage(chat_id, t);
    env->ReleaseStringUTFChars(text, t);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nexus_v2_dpi_DpiNative_nativeTdDestroy(JNIEnv* env, jobject thiz) {
    if (g_client) {
        g_client->stop();
        delete g_client;
        g_client = nullptr;
    }
}
