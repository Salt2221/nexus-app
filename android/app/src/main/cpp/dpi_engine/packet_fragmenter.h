// ═══════════════════════════════════════════════════════════════
// NEXUS Packet Fragmenter — C++ DPI Engine
// ──────────────────────────────────────────────────────────────
// On-device TCP/UDP packet modifier:
//   - SNI fragmenting (split Server Name Indication into parts)
//   - HTTP header case mangling (Host: -> host: -> HOST:)
//   - Fake TCP packets with low TTL to confuse DPI
//   - TCP frame reordering within window
//   - TLS record splitting at arbitrary boundaries
// ═══════════════════════════════════════════════════════════════

#ifndef NEXUS_PACKET_FRAGMENTER_H
#define NEXUS_PACKET_FRAGMENTER_H

#include <cstdint>
#include <cstddef>
#include <vector>
#include <array>
#include <random>
#include <cstring>
#include <algorithm>

// ═══════════════════════════════════════════════════════════════
// Конфигурация
// ═══════════════════════════════════════════════════════════════

struct FragmenterConfig {
    // SNI фрагментация
    bool sni_fragment_enabled = true;
    int sni_fragment_min_parts = 2;
    int sni_fragment_max_parts = 5;

    // HTTP case mangling
    bool http_case_mangle_enabled = true;

    // Fake TTL packets
    bool fake_ttl_enabled = true;
    int fake_ttl_min = 1;
    int fake_ttl_max = 8;
    int fake_packets_per_connection = 3;

    // TCP frame reordering
    bool tcp_reorder_enabled = true;
    int reorder_window_size = 4; // переставляем в пределах 4 пакетов

    // TLS record splitting
    bool tls_split_enabled = true;
    int tls_split_min_bytes = 1;
    int tls_split_max_bytes = 256;

    // Packet padding
    bool padding_enabled = true;
    int padding_min_bytes = 8;
    int padding_max_bytes = 128;

    // Target hosts (empty = all)
    char target_hosts[8][128] = {};
    int target_host_count = 0;
};

// ═══════════════════════════════════════════════════════════════
// Результат модификации пакета
// ═══════════════════════════════════════════════════════════════

struct FragmentResult {
    // Модифицированный пакет (может быть передан вместо исходного)
    std::vector<uint8_t> modified_packet;

    // Дополнительные фейковые пакеты для инъекции в TUN
    std::vector<std::vector<uint8_t>> fake_packets;

    // Мета-информация
    bool was_modified = false;
    int fragment_count = 0;
    const char* strategy_used = "none";
};

// ═══════════════════════════════════════════════════════════════
// Основной класс
// ═══════════════════════════════════════════════════════════════

class PacketFragmenter {
public:
    PacketFragmenter();
    explicit PacketFragmenter(const FragmenterConfig& config);
    ~PacketFragmenter() = default;

    // Установить конфигурацию
    void setConfig(const FragmenterConfig& config);
    const FragmenterConfig& getConfig() const;

    // Обработка пакета (вызывается для каждого TUN пакета)
    FragmentResult process(const uint8_t* data, size_t len);

    // Сброс состояния для нового соединения
    void reset();

private:
    FragmenterConfig config_;
    std::mt19937 rng_;

    // Состояние на соединение
    struct ConnectionState {
        uint32_t src_ip;
        uint32_t dst_ip;
        uint16_t src_port;
        uint16_t dst_port;
        std::vector<uint16_t> seq_history; // TCP seq numbers
        int packet_count = 0;
        bool sni_fragmented = false;
        bool http_mangled = false;
    };

    std::vector<ConnectionState> connections_;

    // ─── Внутренние методы ─────────────────────────────────

    // Найти/создать состояние для соединения
    ConnectionState* getOrCreateConnection(uint32_t src_ip, uint32_t dst_ip,
                                           uint16_t src_port, uint16_t dst_port);

    // Определить тип пакета
    enum PacketType {
        UNKNOWN,
        TCP_SYN,
        TLS_CLIENT_HELLO,
        HTTP_REQUEST,
        TCP_DATA,
        UDP_DNS,
        UDP_DATA
    };

    PacketType detectPacketType(const uint8_t* data, size_t len);

    // Стратегии модификации
    std::vector<uint8_t> fragmentSNI(const uint8_t* data, size_t len, int& parts);
    std::vector<uint8_t> mangleHTTPCase(const uint8_t* data, size_t len);
    std::vector<uint8_t> splitTLSRecords(const uint8_t* data, size_t len);
    std::vector<uint8_t> addPadding(const uint8_t* data, size_t len);

    // Фейковые пакеты
    std::vector<uint8_t> createFakeTCP(uint32_t src_ip, uint32_t dst_ip,
                                       uint16_t src_port, uint16_t dst_port,
                                       uint32_t seq, uint32_t ack, uint8_t ttl);

    // Перемешивание TCP фреймов (метка для TUN вывода)
    void markForReorder(ConnectionState* state);
};

#endif // NEXUS_PACKET_FRAGMENTER_H
