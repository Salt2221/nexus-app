// ═══════════════════════════════════════════════════════════════
// NEXUS Packet Fragmenter — C++ Implementation
// ═══════════════════════════════════════════════════════════════

#include "packet_fragmenter.h"
#include <android/log.h>

#define LOG_TAG "NexusDPI"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─── Конструкторы ──────────────────────────────────────────

PacketFragmenter::PacketFragmenter()
    : rng_(std::random_device{}()) {
    LOGD("PacketFragmenter created (default config)");
}

PacketFragmenter::PacketFragmenter(const FragmenterConfig& config)
    : config_(config), rng_(std::random_device{}()) {
    LOGD("PacketFragmenter created (custom config)");
}

void PacketFragmenter::setConfig(const FragmenterConfig& config) {
    config_ = config;
    LOGD("Config updated");
}

const FragmenterConfig& PacketFragmenter::getConfig() const {
    return config_;
}

void PacketFragmenter::reset() {
    connections_.clear();
}

// ─── Основной процессор ────────────────────────────────────

FragmentResult PacketFragmenter::process(const uint8_t* data, size_t len) {
    FragmentResult result;

    if (!data || len < 20) return result;

    // Читаем IP заголовок
    uint8_t version_ihl = data[0];
    uint8_t ihl = (version_ihl & 0x0F) * 4;
    if (ihl < 20 || ihl > len) return result;

    uint8_t protocol = data[9];
    uint16_t total_len = (data[2] << 8) | data[3];
    if (total_len > len) total_len = len;

    uint32_t src_ip = (data[12] << 24) | (data[13] << 16) | (data[14] << 8) | data[15];
    uint32_t dst_ip = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];

    PacketType ptype = detectPacketType(data, len);

    // TCP
    if (protocol == 6 && ihl + 20 <= total_len) {
        uint16_t src_port = (data[ihl] << 8) | data[ihl + 1];
        uint16_t dst_port = (data[ihl + 2] << 8) | data[ihl + 3];
        uint8_t tcp_hdr_len = ((data[ihl + 12] & 0xF0) >> 2);
        if (tcp_hdr_len < 20) return result;

        uint16_t payload_off = ihl + tcp_hdr_len;
        uint16_t payload_len = total_len - payload_off;

        auto* conn = getOrCreateConnection(src_ip, dst_ip, src_port, dst_port);
        if (!conn) return result;

        conn->packet_count++;

        // Если payload пустой — ничего не делаем
        if (payload_len == 0) return result;

        const uint8_t* payload = data + payload_off;
        std::vector<uint8_t> modified_payload(payload, payload + payload_len);

        // 1. HTTP case mangling (самый быстрый — первый)
        if (config_.http_case_mangle_enabled && !conn->http_mangled &&
            (ptype == HTTP_REQUEST || ptype == TCP_DATA)) {
            auto mangled = mangleHTTPCase(modified_payload.data(), modified_payload.size());
            if (!mangled.empty()) {
                modified_payload = std::move(mangled);
                conn->http_mangled = true;
                result.was_modified = true;
                result.strategy_used = "http_case_mangle";
                LOGD("HTTP case mangled on conn %x:%d", dst_ip, dst_port);
            }
        }

        // 2. SNI fragmentation (TLS ClientHello)
        if (config_.sni_fragment_enabled && !conn->sni_fragmented &&
            ptype == TLS_CLIENT_HELLO) {
            int parts = 0;
            auto fragmented = fragmentSNI(modified_payload.data(), modified_payload.size(), parts);
            if (!fragmented.empty()) {
                modified_payload = std::move(fragmented);
                conn->sni_fragmented = true;
                result.was_modified = true;
                result.fragment_count = parts;
                result.strategy_used = "sni_fragment";
                LOGD("SNI fragmented into %d parts on conn %x:%d", parts, dst_ip, dst_port);
            }
        }

        // 3. TLS record splitting
        if (config_.tls_split_enabled && ptype == TLS_CLIENT_HELLO) {
            auto split = splitTLSRecords(modified_payload.data(), modified_payload.size());
            if (!split.empty()) {
                modified_payload = std::move(split);
                result.was_modified = true;
                result.strategy_used = "tls_split";
            }
        }

        // 4. Фейковые TTL пакеты
        if (config_.fake_ttl_enabled && conn->packet_count < config_.fake_packets_per_connection + 1) {
            uint32_t seq = (data[ihl + 4] << 24) | (data[ihl + 5] << 16) |
                           (data[ihl + 6] << 8) | data[ihl + 7];
            uint32_t ack = (data[ihl + 8] << 24) | (data[ihl + 9] << 16) |
                           (data[ihl + 10] << 8) | data[ihl + 11];

            for (int f = 0; f < 2; f++) {
                auto fake = createFakeTCP(src_ip, dst_ip, src_port, dst_port,
                                          seq + 100 + f, ack,
                                          (uint8_t)(config_.fake_ttl_min +
                                              rng_() % (config_.fake_ttl_max - config_.fake_ttl_min + 1)));
                if (!fake.empty()) {
                    result.fake_packets.push_back(std::move(fake));
                }
            }
        }

        // 5. Padding
        if (config_.padding_enabled && modified_payload.size() > 20) {
            auto padded = addPadding(modified_payload.data(), modified_payload.size());
            if (!padded.empty()) {
                modified_payload = std::move(padded);
                result.was_modified = true;
            }
        }

        // 6. Собираем финальный пакет с переписанным IP заголовком
        if (result.was_modified || !result.fake_packets.empty()) {
            result.modified_packet.resize(total_len);
            // Копируем оригинальный пакет, заменяем payload
            memcpy(result.modified_packet.data(), data, payload_off);
            memcpy(result.modified_packet.data() + payload_off, modified_payload.data(),
                   std::min(modified_payload.size(), (size_t)(total_len - payload_off)));

            // Пересчитываем длину (может измениться при split)
            uint16_t new_total = payload_off + modified_payload.size();
            result.modified_packet[2] = (new_total >> 8) & 0xFF;
            result.modified_packet[3] = new_total & 0xFF;
        }
    }

    // UDP (DNS DoH bypass)
    if (protocol == 17 && ihl + 8 <= total_len) {
        uint16_t dst_port = (data[ihl + 2] << 8) | data[ihl + 3];
        if (dst_port == 53 && config_.fake_ttl_enabled) {
            // DNS запросы пропускаем как есть, но можем подмешать фейковые
        }
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Определение типа пакета
// ═══════════════════════════════════════════════════════════════

PacketFragmenter::PacketType PacketFragmenter::detectPacketType(const uint8_t* data, size_t len) {
    if (len < 34) return UNKNOWN;

    uint8_t ihl = (data[0] & 0x0F) * 4;
    uint8_t protocol = data[9];

    if (protocol != 6) { // non-TCP
        if (protocol == 17) {
            uint16_t dst_port = (data[ihl + 2] << 8) | data[ihl + 3];
            return (dst_port == 53) ? UDP_DNS : UDP_DATA;
        }
        return UNKNOWN;
    }

    uint16_t payload_off = ihl + ((data[ihl + 12] & 0xF0) >> 2);
    if (payload_off >= len) return UNKNOWN;

    uint8_t tcp_flags = data[ihl + 13];
    if (tcp_flags & 0x02) return TCP_SYN; // SYN

    const uint8_t* payload = data + payload_off;
    size_t payload_len = len - payload_off;

    // TLS ClientHello
    if (payload_len >= 5 && payload[0] == 0x16 && payload[1] == 0x03) {
        return TLS_CLIENT_HELLO;
    }

    // HTTP request
    if (payload_len >= 7) {
        if (memcmp(payload, "GET ", 4) == 0 ||
            memcmp(payload, "POST ", 5) == 0 ||
            memcmp(payload, "PUT ", 4) == 0 ||
            memcmp(payload, "DELETE ", 7) == 0 ||
            memcmp(payload, "HEAD ", 5) == 0 ||
            memcmp(payload, "OPTIONS ", 8) == 0 ||
            memcmp(payload, "PATCH ", 6) == 0 ||
            memcmp(payload, "CONNECT ", 8) == 0) {
            return HTTP_REQUEST;
        }
    }

    return TCP_DATA;
}

// ═══════════════════════════════════════════════════════════════
// SNI фрагментация
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> PacketFragmenter::fragmentSNI(const uint8_t* data, size_t len, int& parts) {
    if (!data || len < 50) return {};

    // Ищем SNI extension в TLS ClientHello
    // Формат: extension_type(2) + length(2) + server_name_list_length(2) +
    //         name_type(1) + name_length(2) + name
    const uint8_t sni_marker[] = {0x00, 0x00}; // Extension type = server_name (0)

    for (size_t i = 0; i < len - 10; i++) {
        if (memcmp(data + i, sni_marker, 2) == 0) {
            // Нашли SNI extension
            if (i + 4 > len) return {};
            uint16_t ext_len = (data[i + 2] << 8) | data[i + 3];
            if (i + 4 + ext_len > len) return {};

            // Проверяем server name list
            uint16_t list_len = (data[i + 4] << 8) | data[i + 5];
            if (list_len + 6 > ext_len) return {};

            // name_type + name_len
            if (i + 7 > len) return {};
            uint16_t name_len = (data[i + 6] << 8) | data[i + 7];
            if (i + 8 + name_len > len) return {};

            // Создаём копию с фрагментированным SNI
            std::vector<uint8_t> result(data, data + len);

            // Разбиваем SNI имя на части
            int num_parts = config_.sni_fragment_min_parts +
                rng_() % (config_.sni_fragment_max_parts - config_.sni_fragment_min_parts + 1);
            if (num_parts < 1) num_parts = 1;

            int part_size = name_len / num_parts;
            if (part_size < 2) { part_size = 2; num_parts = name_len / 2; }
            if (num_parts < 1) num_parts = 1;

            parts = num_parts;

            // Вставляем NULL bytes между частями SNI (путает DPI)
            size_t sni_start = i + 8;
            // Раздвигаем: вставляем 0x00 между частями
            int extra = num_parts - 1;
            result.resize(len + extra);

            // Сдвигаем данные после SNI
            memmove(result.data() + sni_start + name_len + extra,
                    result.data() + sni_start + name_len,
                    len - sni_start - name_len);

            // Разбиваем имя с 0x00 разделителями
            for (int p = 0; p < num_parts; p++) {
                int start = p * part_size;
                int end = (p == num_parts - 1) ? name_len : start + part_size;
                int seg_len = end - start;

                memcpy(result.data() + sni_start + p * (part_size + 1),
                       data + sni_start + start, seg_len);

                if (p < num_parts - 1) {
                    result.data()[sni_start + (p + 1) * part_size + p] = 0x00;
                }
            }

            // Обновляем length поля
            uint16_t new_name_len = name_len + extra;
            uint16_t new_list_len = list_len + extra;
            uint16_t new_ext_len = ext_len + extra;

            // Позиции: name_len, list_len, ext_len
            result[i + 2] = (new_ext_len >> 8) & 0xFF;
            result[i + 3] = new_ext_len & 0xFF;
            result[i + 4] = (new_list_len >> 8) & 0xFF;
            result[i + 5] = new_list_len & 0xFF;
            // name_len (i+6, i+7) — оставляем оригинальным, т.к. имя то же самое
            // но с NULL байтами внутри

            LOGD("SNI fragmented: %d parts, %d -> %d bytes", num_parts, name_len, new_name_len);

            return result;
        }
    }

    return {};
}

// ═══════════════════════════════════════════════════════════════
// HTTP Header Case Mangling
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> PacketFragmenter::mangleHTTPCase(const uint8_t* data, size_t len) {
    if (!data || len < 10) return {};

    std::vector<uint8_t> result(data, data + len);
    bool modified = false;

    // Ищем HTTP заголовки в формате "Key: Value"
    // Меняем регистр: Host: -> host: -> HOST: случайным образом

    // Сначала проверяем что это HTTP
    bool is_http = false;
    if (len >= 4 && memcmp(data, "GET ", 4) == 0) is_http = true;
    if (len >= 5 && memcmp(data, "POST ", 5) == 0) is_http = true;
    if (len >= 7 && memcmp(data, "DELETE ", 7) == 0) is_http = true;

    if (!is_http) return {};

    for (size_t i = 0; i < len - 4; i++) {
        // Ищем ": " — разделитель заголовка
        if (data[i] == ':' && i > 0 && data[i - 1] == ' ' && i + 1 < len) continue;
        if (data[i] == ':' && i > 0 && i < len - 1 && data[i + 1] == ' ') {
            // Нашли заголовок. Меняем регистр букв от начала строки до :
            size_t line_start = i;
            while (line_start > 0 && data[line_start - 1] != '\n') line_start--;

            bool all_upper = rng_() % 2 == 0;
            bool mixed = rng_() % 2 == 0;

            for (size_t j = line_start; j < i; j++) {
                char c = (char)data[j];
                if (c >= 'a' && c <= 'z') {
                    if (all_upper) {
                        result[j] = c - 0x20; // to upper
                        modified = true;
                    }
                } else if (c >= 'A' && c <= 'Z') {
                    if (!all_upper && !mixed) {
                        result[j] = c + 0x20; // to lower
                        modified = true;
                    } else if (mixed && rng_() % 3 == 0) {
                        result[j] = c + 0x20; // random lower
                        modified = true;
                    }
                }
            }

            // Пропускаем значение
            while (i < len && data[i] != '\n') i++;
        }
    }

    // Переставляем порядок заголовков
    if (modified && rng_() % 2 == 0) {
        // Простая перестановка: меняем местами последние два заголовка
        std::vector<size_t> header_starts;
        for (size_t i = 0; i < len - 1; i++) {
            if (i == 0 || data[i - 1] == '\n') {
                // Новая строка — может быть заголовком
                if (data[i] >= 'A' && data[i] <= 'z' && data[i] != '\r') {
                    header_starts.push_back(i);
                }
            }
        }

        if (header_starts.size() >= 3) {
            // Меняем местами предпоследние два заголовка
            size_t a = header_starts[header_starts.size() - 3];
            size_t b = header_starts[header_starts.size() - 2];

            // Ищем концы
            size_t end_a = a;
            while (end_a < len && data[end_a] != '\n') end_a++;
            size_t end_b = b;
            while (end_b < len && data[end_b] != '\n') end_b++;

            // Меняем
            std::vector<uint8_t> temp(data + a, data + end_a + 1);
            memcpy(result.data() + a, data + b, end_b - b + 1);
            memcpy(result.data() + a + (end_b - b + 1), data + a, end_a - a + 1);
            modified = true;
        }
    }

    if (!modified) return {};
    return result;
}

// ═══════════════════════════════════════════════════════════════
// TLS Record Splitting
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> PacketFragmenter::splitTLSRecords(const uint8_t* data, size_t len) {
    if (!data || len < 10) return {};

    // Разбиваем TLS record на мелкие куски
    // Каждый record: content_type(1) + version(2) + length(2) + data

    std::vector<uint8_t> result;
    size_t pos = 0;

    while (pos < len) {
        if (pos + 5 > len) {
            // Остаток
            result.insert(result.end(), data + pos, data + len);
            break;
        }

        uint8_t content_type = data[pos];
        uint16_t record_len = (data[pos + 3] << 8) | data[pos + 4];

        if (pos + 5 + record_len > len) {
            result.insert(result.end(), data + pos, data + len);
            break;
        }

        if (content_type == 0x16 && record_len > 50) {
            // ClientHello — разбиваем на мелкие TLS records
            const uint8_t* record_data = data + pos + 5;
            int split_size = config_.tls_split_min_bytes +
                rng_() % (config_.tls_split_max_bytes - config_.tls_split_min_bytes + 1);
            if (split_size < 1) split_size = 1;

            int remaining = record_len;
            int offset = 0;

            while (remaining > 0) {
                int chunk = (remaining < split_size) ? remaining : split_size;
                if (chunk < 1) chunk = 1;

                // Write TLS record header
                result.push_back(content_type);       // content type
                result.push_back(0x03);               // major
                result.push_back(0x01);               // minor
                result.push_back((chunk >> 8) & 0xFF); // length high
                result.push_back(chunk & 0xFF);        // length low

                // Write chunk data
                result.insert(result.end(), record_data + offset, record_data + offset + chunk);

                offset += chunk;
                remaining -= chunk;
            }
        } else {
            // Pass through unchanged
            result.insert(result.end(), data + pos, data + pos + 5 + record_len);
        }

        pos += 5 + record_len;
    }

    LOGD("TLS split: %zu -> %zu bytes", len, result.size());
    return result;
}

// ═══════════════════════════════════════════════════════════════
// Packet Padding
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> PacketFragmenter::addPadding(const uint8_t* data, size_t len) {
    if (!data || len < 10) return {};

    int pad = config_.padding_min_bytes +
        rng_() % (config_.padding_max_bytes - config_.padding_min_bytes + 1);
    if (pad < 1) pad = 1;

    std::vector<uint8_t> result(data, data + len);
    result.resize(len + pad);

    // TLS padding bytes (0x00) или случайные данные
    for (int i = 0; i < pad; i++) {
        result[len + i] = rng_() & 0xFF;
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════
// Фейковые TCP пакеты с низким TTL
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> PacketFragmenter::createFakeTCP(uint32_t src_ip, uint32_t dst_ip,
                                                      uint16_t src_port, uint16_t dst_port,
                                                      uint32_t seq, uint32_t ack, uint8_t ttl) {
    // IP header (20 bytes) + TCP header (20 bytes) + payload (0 bytes)
    std::vector<uint8_t> pkt(40, 0);

    // IP header
    pkt[0] = 0x45; // IPv4, IHL=5
    pkt[1] = 0x00;
    pkt[2] = 0x00; // total length (set below)
    pkt[3] = 40;
    pkt[4] = (rng_() >> 8) & 0xFF; // ID
    pkt[5] = rng_() & 0xFF;
    pkt[6] = 0x40; // flags: DF
    pkt[7] = 0x00; // fragment offset
    pkt[8] = ttl;  // LOW TTL — умрёт до провайдера
    pkt[9] = 6;    // TCP
    // checksum (10-11) — 0
    pkt[12] = (src_ip >> 24) & 0xFF;
    pkt[13] = (src_ip >> 16) & 0xFF;
    pkt[14] = (src_ip >> 8) & 0xFF;
    pkt[15] = src_ip & 0xFF;
    pkt[16] = (dst_ip >> 24) & 0xFF;
    pkt[17] = (dst_ip >> 16) & 0xFF;
    pkt[18] = (dst_ip >> 8) & 0xFF;
    pkt[19] = dst_ip & 0xFF;

    // TCP header
    pkt[20] = (src_port >> 8) & 0xFF;
    pkt[21] = src_port & 0xFF;
    pkt[22] = (dst_port >> 8) & 0xFF;
    pkt[23] = dst_port & 0xFF;
    pkt[24] = (seq >> 24) & 0xFF;
    pkt[25] = (seq >> 16) & 0xFF;
    pkt[26] = (seq >> 8) & 0xFF;
    pkt[27] = seq & 0xFF;
    pkt[28] = (ack >> 24) & 0xFF;
    pkt[29] = (ack >> 16) & 0xFF;
    pkt[30] = (ack >> 8) & 0xFF;
    pkt[31] = ack & 0xFF;
    pkt[32] = 0x50; // data offset = 5 (20 bytes)
    pkt[33] = 0x10; // ACK flag
    // window (34-35)
    pkt[34] = 0x10;
    pkt[35] = 0x00;
    // checksum (36-37) = 0
    // urgent pointer (38-39) = 0

    return pkt;
}

// ═══════════════════════════════════════════════════════════════
// Connection State Management
// ═══════════════════════════════════════════════════════════════

PacketFragmenter::ConnectionState*
PacketFragmenter::getOrCreateConnection(uint32_t src_ip, uint32_t dst_ip,
                                         uint16_t src_port, uint16_t dst_port) {
    // Ищем существующее
    for (auto& c : connections_) {
        if (c.src_ip == src_ip && c.dst_ip == dst_ip &&
            c.src_port == src_port && c.dst_port == dst_port) {
            return &c;
        }
    }

    // Создаём новое
    if (connections_.size() > 1000) {
        connections_.erase(connections_.begin()); // LRU eviction
    }

    ConnectionState state;
    state.src_ip = src_ip;
    state.dst_ip = dst_ip;
    state.src_port = src_port;
    state.dst_port = dst_port;
    state.packet_count = 0;
    state.sni_fragmented = false;
    state.http_mangled = false;

    connections_.push_back(state);
    return &connections_.back();
}

void PacketFragmenter::markForReorder(ConnectionState* state) {
    if (!state) return;
    // Отмечаем что нужно переставить фреймы (для TUN вывода)
    // В реальности TUN читает пакеты последовательно,
    // так что reorder делается на уровне вывода
    if (config_.tcp_reorder_enabled && state->seq_history.size() > 1) {
        // Сохраняем порядок — TUN writer будет использовать
    }
}
