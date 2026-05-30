// ═══════════════════════════════════════════════════════════════
// NEXUS Anti-Blocking Bridge Rotator — Implementation
// ═══════════════════════════════════════════════════════════════

#include "bridge_rotator.h"
#include <android/log.h>
#include <algorithm>
#include <sstream>
#include <regex>

#define LOG_TAG "NexusBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─── Конструктор ──────────────────────────────────────────

BridgeRotator::BridgeRotator()
    : rng_(std::random_device{}()) {
    LOGD("BridgeRotator created");
}

BridgeRotator::BridgeRotator(const RotatorConfig& config)
    : config_(config), rng_(std::random_device{}()) {
    LOGD("BridgeRotator created with config");

    // Если есть hardcoded fallback — добавляем сразу
    for (const auto& ep : config_.hardcoded_fallback) {
        bridges_.push_back(ep);
    }

    if (!bridges_.empty()) {
        active_endpoint_ = &bridges_[0];
    }
}

// ─── Setters ───────────────────────────────────────────────

void BridgeRotator::setConfig(const RotatorConfig& config) {
    config_ = config;
}

const RotatorConfig& BridgeRotator::getConfig() const {
    return config_;
}

void BridgeRotator::setHttpCallback(HttpFetchCallback cb) {
    http_callback_ = std::move(cb);
}

void BridgeRotator::setSteganoCallback(SteganoDecodeCallback cb) {
    stegano_callback_ = std::move(cb);
}

void BridgeRotator::setBridgeFoundCallback(BridgeFoundCallback cb) {
    bridge_callback_ = std::move(cb);
}

// ═══════════════════════════════════════════════════════════════
// Поиск bridge
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::discoverBridge() {
    // Пытаемся найти bridge из разных источников
    // Порядок: от самого незаметного к самому надёжному

    DiscoveryResult result;

    // 1. Стеганография из изображений (самый скрытный)
    result = searchSteganoImages();
    if (!result.endpoint.host.empty() && validateEndpoint(result.endpoint)) {
        LOGD("Found bridge via steganography: %s", result.endpoint.host.c_str());
        goto found;
    }

    // 2. GitHub Issues (публичный, но требует токена)
    if (!config_.github_token.empty()) {
        result = searchGithubIssues();
        if (!result.endpoint.host.empty() && validateEndpoint(result.endpoint)) {
            LOGD("Found bridge via GitHub Issues: %s", result.endpoint.host.c_str());
            goto found;
        }
    }

    // 3. GitHub Releases (публичные артефакты)
    result = searchGithubReleases();
    if (!result.endpoint.host.empty() && validateEndpoint(result.endpoint)) {
        LOGD("Found bridge via GitHub Release: %s", result.endpoint.host.c_str());
        goto found;
    }

    // 4. DHT network
    if (config_.dht_enabled) {
        result = searchDHT();
        if (!result.endpoint.host.empty() && validateEndpoint(result.endpoint)) {
            LOGD("Found bridge via DHT: %s", result.endpoint.host.c_str());
            goto found;
        }
    }

    // 5. Hardcoded fallback
    result = searchHardcoded();
    if (!result.endpoint.host.empty()) {
        LOGD("Using hardcoded fallback bridge: %s", result.endpoint.host.c_str());
        goto found;
    }

    LOGD("No bridge found from any source");
    return result;

found:
    // Добавляем в список
    bridges_.push_back(result.endpoint);
    if (bridges_.size() > (size_t)config_.max_bridges) {
        bridges_.erase(bridges_.begin());
    }

    if (!active_endpoint_ || active_endpoint_->blocked) {
        active_endpoint_ = &bridges_.back();
    }

    if (bridge_callback_) {
        bridge_callback_(result);
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Стеганография из изображений
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchSteganoImages() {
    DiscoveryResult result;
    result.source = BridgeSource::STEGANOGRAPHY_IMAGE;

    for (const auto& url : config_.stegano_urls) {
        auto image_data = httpGetBinary(url);
        if (image_data.empty()) continue;

        result.source_url = url;

        // Пробуем декодировать стеганографию
        if (stegano_callback_) {
            auto decoded = stegano_callback_(image_data);
            if (!decoded.endpoint.host.empty()) {
                return decoded;
            }
        }

        // Fallback: ищем паттерны в raw данных
        // Формат: комментарий PNG "BRIDGE:host:port:key"
        std::string raw(image_data.begin(), image_data.end());

        std::regex bridge_pattern("BRIDGE:([^:]+):(\\d+):([A-Za-z0-9+/=]+)");
        std::smatch match;
        if (std::regex_search(raw, match, bridge_pattern) && match.size() >= 4) {
            result.endpoint.host = match[1];
            result.endpoint.port = std::stoi(match[2]);
            result.endpoint.public_key = match[3];
            result.endpoint.protocol = "reality";
            result.endpoint.fingerprint = "chrome";
            result.confidence = 70;
            return result;
        }

        // Ещё формат: IP:port в последних байтах PNG
        if (image_data.size() > 20) {
            // Последние 6 байт могут содержать IP:port в простой кодировке
            // (используется в stego-схемах с LSB)
        }
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// GitHub Issues
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchGithubIssues() {
    DiscoveryResult result;
    result.source = BridgeSource::GITHUB_ISSUE;

    if (config_.github_repo.empty()) return result;

    // GitHub API: GET /repos/{owner}/{repo}/issues?labels={label}&state=open
    std::string url = "https://api.github.com/repos/" + config_.github_repo +
                      "/issues?labels=" + config_.github_issue_label +
                      "&state=open&per_page=5";

    auto response = httpGet(url);
    if (response.empty()) return result;

    // Парсим JSON issues
    // Ищем: "body": "...BRIDGE:host:port:key..."
    std::regex body_pattern("\"body\"\\s*:\\s*\"([^\"]*BRIDGE[^\"]*)\"",
                            std::regex::icase);
    std::smatch match;

    std::string::const_iterator search_start = response.cbegin();
    while (std::regex_search(search_start, response.cend(), match, body_pattern)) {
        std::string body = match[1];

        // Экранированные символы
        std::string unescaped;
        for (size_t i = 0; i < body.length(); i++) {
            if (body[i] == '\\' && i + 1 < body.length()) {
                // skip escape
                i++;
            } else {
                unescaped += body[i];
            }
        }

        // Ищем BRIDGE:host:port:key
        std::regex bridge_re("BRIDGE:([^:]+):(\\d+):([A-Za-z0-9+/=]+)");
        std::smatch bridge_match;
        if (std::regex_search(unescaped, bridge_match, bridge_re) && bridge_match.size() >= 4) {
            result.endpoint.host = bridge_match[1];
            result.endpoint.port = std::stoi(bridge_match[2]);
            result.endpoint.public_key = bridge_match[3];
            result.endpoint.protocol = "reality";
            result.endpoint.fingerprint = "chrome";
            result.endpoint.server_name = "www.microsoft.com";
            result.confidence = 85;
            result.source_url = url;
            return result;
        }

        search_start = match.suffix().first;
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// GitHub Releases
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchGithubReleases() {
    DiscoveryResult result;
    result.source = BridgeSource::GITHUB_RELEASE;

    if (config_.github_repo.empty()) return result;

    // Получаем список релизов
    std::string url = "https://api.github.com/repos/" + config_.github_repo +
                      "/releases?per_page=5";

    auto response = httpGet(url);
    if (response.empty()) return result;

    // Ищем в body и tag_name
    std::regex tag_pattern("\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
    std::regex body_pattern("\"body\"\\s*:\\s*\"([^\"]+)\"");

    std::smatch tag_match;
    if (std::regex_search(response, tag_match, tag_pattern) && tag_match.size() >= 2) {
        std::string tag = tag_match[1];

        // Если tag содержит bridge обновление
        if (tag.find("bridge") != std::string::npos ||
            tag.find("Bridge") != std::string::npos) {

            std::smatch body_match;
            if (std::regex_search(response, body_match, body_pattern) && body_match.size() >= 2) {
                std::string body = body_match[1];

                std::regex bridge_re("BRIDGE:([^:]+):(\\d+):([A-Za-z0-9+/=]+)");
                std::smatch bridge_match;
                if (std::regex_search(body, bridge_match, bridge_re) && bridge_match.size() >= 4) {
                    result.endpoint.host = bridge_match[1];
                    result.endpoint.port = std::stoi(bridge_match[2]);
                    result.endpoint.public_key = bridge_match[3];
                    result.endpoint.protocol = "reality";
                    result.confidence = 90;
                    result.source_url = url;
                    return result;
                }
            }
        }
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// DHT
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchDHT() {
    DiscoveryResult result;
    result.source = BridgeSource::DHT_NETWORK;

    // DHT поиск реализован на Kotlin стороне (UDP broadcast)
    // Здесь только заглушка — C++ не может делать UDP broadcast легко
    // без JNI

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Public IT Blogs (HTTP parsing)
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchPublicBlogs() {
    DiscoveryResult result;
    result.source = BridgeSource::IT_BLOG;

    // Список IT-блогов с открытыми комментариями
    const std::vector<std::string> blogs = {
        "https://habr.com/ru/articles/top/daily/",
        "https://www.opennet.ru/opennews/",
        "https://news.ycombinator.com/"
    };

    for (const auto& blog_url : blogs) {
        auto content = httpGet(blog_url);
        if (content.empty()) continue;

        std::regex bridge_re("BRIDGE:([^:]+):(\\d+):([A-Za-z0-9+/=]+)");
        std::smatch match;
        if (std::regex_search(content, match, bridge_re) && match.size() >= 4) {
            result.endpoint.host = match[1];
            result.endpoint.port = std::stoi(match[2]);
            result.endpoint.public_key = match[3];
            result.endpoint.protocol = "reality";
            result.confidence = 60;
            result.source_url = blog_url;
            return result;
        }
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Hardcoded
// ═══════════════════════════════════════════════════════════════

DiscoveryResult BridgeRotator::searchHardcoded() {
    DiscoveryResult result;
    result.source = BridgeSource::HARDCODED_FALLBACK;

    if (!config_.hardcoded_fallback.empty()) {
        result.endpoint = config_.hardcoded_fallback[0];
        result.confidence = 50;
        return result;
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Active bridge management
// ═══════════════════════════════════════════════════════════════

BridgeEndpoint BridgeRotator::getActiveBridge() const {
    if (active_endpoint_) return *active_endpoint_;
    return BridgeEndpoint{};
}

void BridgeRotator::setActiveBridge(const BridgeEndpoint& endpoint) {
    // Ищем в списке
    for (auto& b : bridges_) {
        if (b.host == endpoint.host && b.port == endpoint.port) {
            active_endpoint_ = &b;
            return;
        }
    }

    // Если нет — добавляем
    bridges_.push_back(endpoint);
    active_endpoint_ = &bridges_.back();
}

void BridgeRotator::switchToNext() {
    if (bridges_.empty()) return;

    // Находим текущий индекс
    int idx = 0;
    if (active_endpoint_) {
        for (size_t i = 0; i < bridges_.size(); i++) {
            if (bridges_[i].host == active_endpoint_->host &&
                bridges_[i].port == active_endpoint_->port) {
                idx = (i + 1) % bridges_.size();
                break;
            }
        }
    }

    active_endpoint_ = &bridges_[idx];
    LOGD("Switched to bridge %d/%zu: %s:%d", idx + 1, bridges_.size(),
         active_endpoint_->host.c_str(), active_endpoint_->port);
}

void BridgeRotator::markBlocked(const std::string& host) {
    for (auto& b : bridges_) {
        if (b.host == host) {
            b.blocked = true;
            b.fail_count++;
            LOGD("Bridge %s marked as blocked (fail #%d)", host.c_str(), b.fail_count);
            break;
        }
    }

    // Автоматически переключаемся
    if (active_endpoint_ && active_endpoint_->host == host) {
        switchToNext();
    }
}

// ═══════════════════════════════════════════════════════════════
// Health check
// ═══════════════════════════════════════════════════════════════

bool BridgeRotator::checkHealth(int timeout_ms) {
    if (!active_endpoint_) return false;

    // TCP ping на порт
    // В реальности — через JNI к Java Socket
    // Пока возвращаем true
    return true;
}

// ═══════════════════════════════════════════════════════════════
// Validation
// ═══════════════════════════════════════════════════════════════

bool BridgeRotator::validateEndpoint(const BridgeEndpoint& ep) {
    if (ep.host.empty() || ep.port <= 0 || ep.port > 65535) return false;
    if (ep.port == 0 || ep.port == 1 || ep.port == 7) return false; // reserved
    return true;
}

// ═══════════════════════════════════════════════════════════════
// HTTP helpers
// ═══════════════════════════════════════════════════════════════

std::string BridgeRotator::httpGet(const std::string& url) {
    if (http_callback_) {
        return http_callback_(url);
    }
    return {};
}

std::vector<uint8_t> BridgeRotator::httpGetBinary(const std::string& url) {
    if (http_callback_) {
        auto str = http_callback_(url);
        return std::vector<uint8_t>(str.begin(), str.end());
    }
    return {};
}
