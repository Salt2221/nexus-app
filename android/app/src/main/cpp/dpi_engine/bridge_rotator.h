// ═══════════════════════════════════════════════════════════════
// NEXUS Anti-Blocking Bridge Rotator
// ──────────────────────────────────────────────────────────────
// Автономный поиск новых точек входа через:
//   - Стеганография: IP/key в пикселях PNG/JPEG
//   - GitHub Issues / Comments
//   - Public IT blogs
//   - DHT network fallback
//
// Если основной сервер заблокирован — мгновенно находит новый.
// ═══════════════════════════════════════════════════════════════

#ifndef NEXUS_BRIDGE_ROTATOR_H
#define NEXUS_BRIDGE_ROTATOR_H

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>
#include <array>
#include <functional>
#include <chrono>
#include <random>

// ═══════════════════════════════════════════════════════════════
// Типы
// ═══════════════════════════════════════════════════════════════

struct BridgeEndpoint {
    std::string host;
    int port = 443;
    std::string protocol; // reality, ws, grpc, quic
    std::string public_key;
    std::string server_name; // sni
    std::string flow; // xtls flow
    std::string fingerprint; // chrome, firefox, safari
    std::string path; // websocket path

    int latency_ms = 0;
    int64_t last_seen = 0;
    int fail_count = 0;
    bool blocked = false;
};

enum class BridgeSource {
    STEGANOGRAPHY_IMAGE,
    GITHUB_ISSUE,
    GITHUB_RELEASE,
    IT_BLOG,
    DHT_NETWORK,
    HARDCODED_FALLBACK,
    RELAY_PEER
};

struct DiscoveryResult {
    BridgeSource source;
    BridgeEndpoint endpoint;
    std::string source_url;
    int confidence = 0; // 0-100
};

// ═══════════════════════════════════════════════════════════════
// Callbacks
// ═══════════════════════════════════════════════════════════════

// Callback для HTTP запросов (должен быть реализован на стороне Kotlin/Java)
using HttpFetchCallback = std::function<std::string(const std::string& url)>;

// Callback для стеганографии (декодирование IP/key из пикселей)
using SteganoDecodeCallback = std::function<DiscoveryResult(const std::vector<uint8_t>& image_data)>;

// Callback когда найден новый bridge
using BridgeFoundCallback = std::function<void(const DiscoveryResult&)>;

// ═══════════════════════════════════════════════════════════════
// Конфигурация
// ═══════════════════════════════════════════════════════════════

struct RotatorConfig {
    // GitHub
    std::string github_token;
    std::string github_repo = "Salt2221/nexus-bridges";
    std::string github_issue_label = "bridge";
    int github_check_interval_sec = 300; // 5 минут

    // Public IT blogs (URLs для поиска)
    std::vector<std::string> stegano_urls = {
        "https://raw.githubusercontent.com/Salt2221/nexus-bridges/main/bridges.png",
        "https://raw.githubusercontent.com/Salt2221/nexus-bridges/main/fallback.png"
    };

    // DHT
    int dht_port = 21989;
    bool dht_enabled = true;

    // Hardcoded fallback (последняя надежда)
    std::vector<BridgeEndpoint> hardcoded_fallback;

    // Timing
    int health_check_interval_ms = 30000;
    int bridge_switch_threshold = 3; // после 3 фейлов — ищем новый
    int max_bridges = 10;
};

// ═══════════════════════════════════════════════════════════════
// Bridge Rotator
// ═══════════════════════════════════════════════════════════════

class BridgeRotator {
public:
    BridgeRotator();
    explicit BridgeRotator(const RotatorConfig& config);
    ~BridgeRotator() = default;

    // Конфигурация
    void setConfig(const RotatorConfig& config);
    const RotatorConfig& getConfig() const;

    // Callbacks
    void setHttpCallback(HttpFetchCallback cb);
    void setSteganoCallback(SteganoDecodeCallback cb);
    void setBridgeFoundCallback(BridgeFoundCallback cb);

    // Поиск нового bridge
    DiscoveryResult discoverBridge();

    // Активный bridge
    BridgeEndpoint getActiveBridge() const;
    void setActiveBridge(const BridgeEndpoint& endpoint);
    void switchToNext();

    // Статус
    bool isActive() const { return active_endpoint_ != nullptr; }
    int getBridgeCount() const { return bridges_.size(); }

    // Маркировка bridge как заблокированного
    void markBlocked(const std::string& host);

    // Здоровье активного bridge
    bool checkHealth(int timeout_ms);

private:
    RotatorConfig config_;
    HttpFetchCallback http_callback_;
    SteganoDecodeCallback stegano_callback_;
    BridgeFoundCallback bridge_callback_;

    BridgeEndpoint* active_endpoint_ = nullptr;
    std::vector<BridgeEndpoint> bridges_;
    std::mt19937 rng_;

    // Источники поиска
    DiscoveryResult searchGithubIssues();
    DiscoveryResult searchGithubReleases();
    DiscoveryResult searchSteganoImages();
    DiscoveryResult searchPublicBlogs();
    DiscoveryResult searchDHT();
    DiscoveryResult searchHardcoded();

    // Валидация
    bool validateEndpoint(const BridgeEndpoint& ep);

    // HTTP helper
    std::string httpGet(const std::string& url);
    std::vector<uint8_t> httpGetBinary(const std::string& url);
};

#endif // NEXUS_BRIDGE_ROTATOR_H
