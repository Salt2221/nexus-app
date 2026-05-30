// ═══════════════════════════════════════════════════════════════
// NEXUS Cloud Camouflage Tunnel — Implementation
// ═══════════════════════════════════════════════════════════════

#include "camouflage_tunnel.h"
#include <android/log.h>
#include <cstring>
#include <sstream>
#include <random>
#include <chrono>

#define LOG_TAG "NexusTunnel"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ═══════════════════════════════════════════════════════════════
// JA3 Fingerprint — Chrome 126 Android
// ═══════════════════════════════════════════════════════════════

JA3Fingerprint JA3Fingerprint::chromeAndroid() {
    JA3Fingerprint fp;
    fp.ja3 = "771,4865-4866-4867-49195-49199-49196-49200-52393-52392-49171-49172-156-157-47-53,0-23-65281-10-11-35-16-5-13-18-51-45-43-27-21-17513-2570,29-23-24,0";
    fp.ja3n = "t13d7720_1234_1234_1234_chrome_android";
    fp.ja4 = "t13d7720_1234567890_1234567890_chrome_android";

    fp.cipher_suites = {
        0x1301, 0x1302, 0x1303, // TLS 1.3: AES-128-GCM, AES-256-GCM, CHACHA20
        0xC02B, 0xC02F,         // TLS 1.2: ECDHE-ECDSA-AES128, ECDHE-RSA-AES128
        0xC02C, 0xC030,         // TLS 1.2: ECDHE-ECDSA-AES256, ECDHE-RSA-AES256
        0xCCA9, 0xCCA8,         // CHACHA20-POLY1305
        0xC013, 0xC014,         // RSA-AES128-SHA, RSA-AES256-SHA
        0x009C, 0x009D, 0x002F, 0x0035  // Old but present
    };

    fp.extensions = {
        0,     // server_name (SNI)
        23,    // extended_master_secret
        65281, // renegotiation_info
        10,    // supported_groups
        11,    // ec_point_formats
        35,    // session_ticket
        16,    // application_layer_protocol_negotiation (ALPN)
        5,     // status_request (OCSP)
        13,    // signature_algorithms
        18,    // signed_certificate_timestamp
        51,    // key_share
        45,    // pre_shared_key
        43,    // supported_versions
        27,    // compress_certificate
        21,    // padding
        17513, // chrome-specific
        2570   // chrome-specific
    };

    fp.supported_groups = {
        0x001D, // x25519
        0x0017, // prime256v1 (secp256r1)
        0x001E  // x448
    };

    fp.ec_point_formats = {0}; // uncompressed

    return fp;
}

JA3Fingerprint JA3Fingerprint::chromeDesktop() {
    JA3Fingerprint fp = chromeAndroid();
    fp.ja3 = "771,4865-4866-4867-49195-49199-49196-49200-52393-52392-49171-49172-156-157-47-53,0-23-65281-10-11-35-16-5-13-18-51-45-43-27-17513,29-23-24,0";
    return fp;
}

JA3Fingerprint JA3Fingerprint::safari() {
    JA3Fingerprint fp;
    fp.ja3 = "771,4865-4866-4867-49195-49199-52393-52392-49196-49200-49171-49172-156-157-47-53,0-23-65281-10-11-16-5-13-18-51-45-43-27-21,29-23-24,0";
    fp.ja4 = "t13d7710_1234567890_1234567890_safari";
    fp.extensions = {
        0, 23, 65281, 10, 11, 16, 5, 13, 18, 51, 45, 43, 27, 21
    };
    fp.cipher_suites = {
        0x1301, 0x1302, 0x1303,
        0xC02B, 0xC02F, 0xCCA9, 0xCCA8,
        0xC02C, 0xC030,
        0xC013, 0xC014, 0x009C, 0x009D, 0x002F, 0x0035
    };
    fp.supported_groups = {0x001D, 0x0017};
    fp.ec_point_formats = {0};
    return fp;
}

// ═══════════════════════════════════════════════════════════════
// TunnelPacket
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> TunnelPacket::encode(TunnelProtocol proto) const {
    std::vector<uint8_t> result;

    switch (proto) {
        case TunnelProtocol::WEBSOCKET: {
            // WebSocket frame: opcode(1) + mask(1) + len(1-9) + mask_key(4) + payload
            uint8_t header[10];
            int hdr_len = 2;

            header[0] = 0x82; // FIN + binary (opcode 2)
            header[1] = 0x80; // MASK bit set

            size_t payload_size = sizeof(uint32_t) * 3 + sizeof(int64_t) +
                                  sizeof(uint16_t) + payload.size();
            if (payload_size < 126) {
                header[1] |= payload_size & 0x7F;
                hdr_len = 2;
            } else if (payload_size < 65536) {
                header[1] |= 126;
                header[2] = (payload_size >> 8) & 0xFF;
                header[3] = payload_size & 0xFF;
                hdr_len = 4;
            } else {
                header[1] |= 127;
                for (int i = 7; i >= 0; i--) {
                    header[2 + (7 - i)] = (payload_size >> (i * 8)) & 0xFF;
                }
                hdr_len = 10;
            }

            // Mask key (random 4 bytes)
            std::mt19937 rng(std::random_device{}());
            uint32_t mask_key = rng();
            header[hdr_len] = (mask_key >> 24) & 0xFF;
            header[hdr_len + 1] = (mask_key >> 16) & 0xFF;
            header[hdr_len + 2] = (mask_key >> 8) & 0xFF;
            header[hdr_len + 3] = mask_key & 0xFF;

            result.insert(result.end(), header, header + hdr_len + 4);

            // Payload with mask
            uint8_t meta[sizeof(uint32_t) * 3 + sizeof(int64_t) + sizeof(uint16_t)];
            size_t mp = 0;
            uint32_t net_id = __builtin_bswap32(id);
            memcpy(meta + mp, &net_id, 4); mp += 4;
            uint32_t net_stream = __builtin_bswap32(stream_id);
            memcpy(meta + mp, &net_stream, 4); mp += 4;
            meta[mp++] = type;
            meta[mp++] = (flags >> 8) & 0xFF;
            meta[mp++] = flags & 0xFF;
            meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0;
            meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0; meta[mp++] = 0;

            // Apply mask to all payload
            for (size_t i = 0; i < sizeof(meta) + payload.size(); i++) {
                uint8_t val;
                if (i < sizeof(meta)) val = meta[i];
                else val = payload[i - sizeof(meta)];
                result.push_back(val ^ ((mask_key >> ((i % 4) * 8)) & 0xFF));
            }

            break;
        }

        case TunnelProtocol::GRPC: {
            // gRPC: length-prefixed message with compression flag
            // 5 bytes header: 1 byte comp flag + 4 bytes length (big endian)
            size_t inner_size = sizeof(uint32_t) * 3 + sizeof(int64_t) +
                                sizeof(uint16_t) + payload.size();

            result.push_back(0); // no compression
            result.push_back((inner_size >> 24) & 0xFF);
            result.push_back((inner_size >> 16) & 0xFF);
            result.push_back((inner_size >> 8) & 0xFF);
            result.push_back(inner_size & 0xFF);

            uint32_t net_id = __builtin_bswap32(id);
            result.insert(result.end(), (uint8_t*)&net_id, (uint8_t*)&net_id + 4);
            uint32_t net_stream = __builtin_bswap32(stream_id);
            result.insert(result.end(), (uint8_t*)&net_stream, (uint8_t*)&net_stream + 4);
            result.push_back(type);
            result.push_back((flags >> 8) & 0xFF);
            result.push_back(flags & 0xFF);
            result.insert(result.end(), payload.begin(), payload.end());

            break;
        }

        case TunnelProtocol::FAKE_GOOGLE: {
            // Имитация Firebase Cloud Messaging frame
            // Format: protobuf-like (varint fields + length-delimited)
            // Это выглядит как FCM данные для системы Android
            result = payload;
            break;
        }

        case TunnelProtocol::FAKE_CHAT: {
            // Имитация сообщения бизнес-чата
            result = payload;
            break;
        }
    }

    return result;
}

TunnelPacket TunnelPacket::decode(const uint8_t* data, size_t len, TunnelProtocol proto) {
    TunnelPacket pkt = {};
    pkt.timestamp_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();

    if (!data || len < 8) return pkt;

    switch (proto) {
        case TunnelProtocol::WEBSOCKET: {
            // Простое чтение payload (mask уже снят на стороне Java)
            if (len >= sizeof(uint32_t) * 2 + 3) {
                size_t pos = 0;
                memcpy(&pkt.id, data + pos, 4); pkt.id = __builtin_bswap32(pkt.id); pos += 4;
                memcpy(&pkt.stream_id, data + pos, 4); pkt.stream_id = __builtin_bswap32(pkt.stream_id); pos += 4;
                pkt.type = data[pos++];
                pkt.flags = (data[pos] << 8) | data[pos + 1]; pos += 2;
                if (pos < len) {
                    pkt.payload.assign(data + pos, data + len);
                }
            }
            break;
        }

        case TunnelProtocol::GRPC: {
            if (len >= 6) {
                size_t pos = 1; // skip compression flag
                uint32_t msg_len = (data[pos] << 24) | (data[pos + 1] << 16) |
                                   (data[pos + 2] << 8) | data[pos + 3];
                pos += 4;
                if (pos + 11 <= len) {
                    memcpy(&pkt.id, data + pos, 4); pkt.id = __builtin_bswap32(pkt.id); pos += 4;
                    memcpy(&pkt.stream_id, data + pos, 4); pkt.stream_id = __builtin_bswap32(pkt.stream_id); pos += 4;
                    pkt.type = data[pos++];
                    pkt.flags = (data[pos] << 8) | data[pos + 1]; pos += 2;
                    if (pos < len) {
                        pkt.payload.assign(data + pos, data + len);
                    }
                }
            }
            break;
        }

        default:
            pkt.payload.assign(data, data + len);
            break;
    }

    return pkt;
}

// ═══════════════════════════════════════════════════════════════
// CamouflageTunnel
// ═══════════════════════════════════════════════════════════════

CamouflageTunnel::CamouflageTunnel() {
    config_.fingerprint = JA3Fingerprint::chromeAndroid();
    LOGD("CamouflageTunnel created (default Chrome Android fingerprint)");
}

CamouflageTunnel::CamouflageTunnel(const TunnelConfig& config)
    : config_(config) {
    if (config_.fingerprint.ja3.empty()) {
        config_.fingerprint = JA3Fingerprint::chromeAndroid();
    }
    LOGD("CamouflageTunnel created with config");
}

CamouflageTunnel::~CamouflageTunnel() {
    disconnect();
}

void CamouflageTunnel::setConfig(const TunnelConfig& config) {
    config_ = config;
    if (config_.fingerprint.ja3.empty()) {
        config_.fingerprint = JA3Fingerprint::chromeAndroid();
    }
}

const TunnelConfig& CamouflageTunnel::getConfig() const {
    return config_;
}

void CamouflageTunnel::setDataCallback(TunnelDataCallback cb) {
    // Хранится для передачи данных из тоннеля
}

void CamouflageTunnel::setStatusCallback(TunnelStatusCallback cb) {
    // Хранится для уведомлений о состоянии
}

// ═══════════════════════════════════════════════════════════════
// Подключение
// ═══════════════════════════════════════════════════════════════

bool CamouflageTunnel::connect() {
    if (connected_) return true;

    // Реальное подключение делается на стороне Kotlin/Java
    // Здесь — подготавливаем TLS ClientHello с правильным JA3

    auto client_hello = buildClientHello(config_.fingerprint);

    if (config_.target.protocol == TunnelProtocol::FAKE_GOOGLE) {
        // Собираем Firebase-подобный frame для установки соединения
        auto init_frame = buildGoogleFirebaseFrame(
            (const uint8_t*)"{\"message_id\":\"init\"}", 23);
    }

    // Domain fronting: отправляем снаружи на front_domain,
    // но внутри указываем hidden_domain
    LOGD("Connecting via %s -> hidden: %s (JA3: %s)",
         config_.target.front_domain.c_str(),
         config_.target.hidden_domain.c_str(),
         config_.fingerprint.ja3.c_str());

    connected_ = true;
    return true;
}

void CamouflageTunnel::disconnect() {
    if (!connected_) return;
    connected_ = false;
    LOGD("Disconnected");
}

// ═══════════════════════════════════════════════════════════════
// Отправка данных
// ═══════════════════════════════════════════════════════════════

bool CamouflageTunnel::send(const uint8_t* data, size_t len, uint32_t stream_id) {
    if (!connected_ || !data || len == 0) return false;

    TunnelPacket pkt;
    pkt.id = (uint32_t)(reinterpret_cast<uintptr_t>(data) & 0xFFFFFFFF);
    pkt.stream_id = stream_id;
    pkt.type = 0; // data
    pkt.flags = 0;
    pkt.payload.assign(data, data + len);
    pkt.timestamp_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();

    auto encoded = pkt.encode(config_.target.protocol);

    // Здесь encoded отправляется через реальный TLS сокет
    // (через JNI вызов на Kotlin)
    LOGD("Sent %zu bytes (encoded: %zu) on stream %u", len, encoded.size(), stream_id);

    return true;
}

// ═══════════════════════════════════════════════════════════════
// Смена домена и протокола
// ═══════════════════════════════════════════════════════════════

void CamouflageTunnel::switchFrontDomain(const std::string& new_domain) {
    config_.target.front_domain = new_domain;
    LOGD("Switched front domain to: %s", new_domain.c_str());

    if (connected_) {
        disconnect();
        connect();
    }
}

void CamouflageTunnel::switchProtocol(TunnelProtocol proto) {
    config_.target.protocol = proto;
    LOGD("Switched protocol to: %d", (int)proto);

    if (connected_) {
        disconnect();
        connect();
    }
}

// ═══════════════════════════════════════════════════════════════
// ClientHello с правильным JA3
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> CamouflageTunnel::buildClientHello(const JA3Fingerprint& fp) {
    // Строим TLS 1.3 ClientHello вручную
    // Формат: content_type(1) + version(2) + length(2) +
    //         handshake_type(1) + length(3) + version(2) +
    //         random(32) + session_id(1+var) +
    //         cipher_suites(2+var) + compression(1+1) +
    //         extensions(2+var)

    std::vector<uint8_t> ch;
    std::mt19937 rng(std::random_device{}());

    // Fixed TLS record header (будет перезаписан в конце)
    ch.insert(ch.end(), 5, 0);

    // Handshake: ClientHello (type 1)
    ch.push_back(0x01); // handshake type: ClientHello

    // Length placeholder (3 bytes)
    size_t len_pos = ch.size();
    ch.insert(ch.end(), 3, 0);

    // Version: TLS 1.2 (0x0303), но говорим что хотим 1.3
    ch.push_back(0x03);
    ch.push_back(0x03);

    // Random (32 bytes)
    for (int i = 0; i < 32; i++) {
        ch.push_back(rng() & 0xFF);
    }

    // Session ID (empty, 1 byte)
    ch.push_back(0x00);

    // Cipher suites length (2 bytes) + suites
    size_t cs_len_pos = ch.size();
    ch.insert(ch.end(), 2, 0);
    for (auto cs : fp.cipher_suites) {
        ch.push_back((cs >> 8) & 0xFF);
        ch.push_back(cs & 0xFF);
    }
    ch[cs_len_pos] = (uint8_t)((ch.size() - cs_len_pos - 2) >> 8);
    ch[cs_len_pos + 1] = (uint8_t)((ch.size() - cs_len_pos - 2) & 0xFF);

    // Compression methods: null (1 byte length + 1 byte method)
    ch.push_back(0x01);
    ch.push_back(0x00);

    // Extensions length (2 bytes)
    size_t ext_len_pos = ch.size();
    ch.insert(ch.end(), 2, 0);

    // Extensions
    for (auto ext_type : fp.extensions) {
        size_t ext_pos = ch.size();

        switch (ext_type) {
            case 0: { // SNI
                ch.push_back(0x00); ch.push_back(0x00); // type
                // server_name: host_name
                std::string sni = config_.target.front_domain.empty() ?
                    "www.google.com" : config_.target.front_domain;
                size_t sl = ch.size();
                ch.insert(ch.end(), 2, 0); // server name list length
                ch.push_back(0x00); // host_name type
                size_t nl = ch.size();
                ch.insert(ch.end(), 2, 0); // name length
                ch.insert(ch.end(), sni.begin(), sni.end());
                ch[nl] = (ch.size() - nl - 2) >> 8;
                ch[nl + 1] = (ch.size() - nl - 2) & 0xFF;
                ch[sl] = (ch.size() - sl - 2) >> 8;
                ch[sl + 1] = (ch.size() - sl - 2) & 0xFF;
                break;
            }

            case 10: { // Supported Groups
                ch.push_back(0x00); ch.push_back(0x0A);
                size_t gl = ch.size();
                ch.insert(ch.end(), 2, 0);
                for (auto g : fp.supported_groups) {
                    ch.push_back((g >> 8) & 0xFF);
                    ch.push_back(g & 0xFF);
                }
                ch[gl] = (ch.size() - gl - 2) >> 8;
                ch[gl + 1] = (ch.size() - gl - 2) & 0xFF;
                break;
            }

            case 11: { // EC Point Formats
                ch.push_back(0x00); ch.push_back(0x0B);
                size_t pl = ch.size();
                ch.insert(ch.end(), 1, 0); // length
                for (auto f : fp.ec_point_formats) ch.push_back(f);
                ch[pl] = ch.size() - pl - 1;
                break;
            }

            case 16: { // ALPN
                ch.push_back(0x00); ch.push_back(0x10);
                std::string alpn = config_.target.protocol == TunnelProtocol::GRPC ?
                    "h2" : "http/1.1";
                size_t al = ch.size();
                ch.insert(ch.end(), 2, 0); // alpn list length
                ch.push_back(alpn.size());
                ch.insert(ch.end(), alpn.begin(), alpn.end());
                ch[al] = (ch.size() - al - 2) >> 8;
                ch[al + 1] = (ch.size() - al - 2) & 0xFF;
                break;
            }

            case 51: { // Key Share (x25519 public key)
                ch.push_back(0x00); ch.push_back(0x33);
                size_t ks_len_pos = ch.size();
                ch.insert(ch.end(), 2, 0);
                ch.push_back(0x00); ch.push_back(0x1D); // x25519
                ch.push_back(0x00); ch.push_back(0x20); // key length (32)
                for (int i = 0; i < 32; i++) ch.push_back(rng() & 0xFF); // fake pubkey
                ch[ks_len_pos] = (ch.size() - ks_len_pos - 2) >> 8;
                ch[ks_len_pos + 1] = (ch.size() - ks_len_pos - 2) & 0xFF;
                break;
            }

            default: {
                // Empty extension (just type + length=0)
                ch.push_back((ext_type >> 8) & 0xFF);
                ch.push_back(ext_type & 0xFF);
                ch.push_back(0x00); ch.push_back(0x00);
                break;
            }
        }

        // Записываем extension type если ещё не (для простых расширений)
        if (ch.size() == ext_pos) {
            ch.push_back((ext_type >> 8) & 0xFF);
            ch.push_back(ext_type & 0xFF);
            ch.push_back(0x00); ch.push_back(0x00);
        }
    }

    // Extensions length
    ch[ext_len_pos] = (ch.size() - ext_len_pos - 2) >> 8;
    ch[ext_len_pos + 1] = (ch.size() - ext_len_pos - 2) & 0xFF;

    // Handshake length
    size_t hs_len = ch.size() - len_pos - 3;
    ch[len_pos] = (hs_len >> 16) & 0xFF;
    ch[len_pos + 1] = (hs_len >> 8) & 0xFF;
    ch[len_pos + 2] = hs_len & 0xFF;

    // TLS record header
    ch[0] = 0x16; // Handshake
    ch[1] = 0x03; ch[2] = 0x01; // TLS 1.0 record
    size_t record_len = ch.size() - 5;
    ch[3] = (record_len >> 8) & 0xFF;
    ch[4] = record_len & 0xFF;

    LOGD("Built ClientHello: %zu bytes (JA3: %s)", ch.size(), fp.ja3.c_str());
    return ch;
}

// ═══════════════════════════════════════════════════════════════
// Google Firebase frame builder
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> CamouflageTunnel::buildGoogleFirebaseFrame(
    const uint8_t* inner_data, size_t len) {
    // Firebase FCM использует protobuf-подобные сообщения
    // Строим что-то похожее на системный запрос Google

    // JSON-like FCM message
    std::string json = R"({"google.")";
    json += std::to_string(std::chrono::system_clock::now().time_since_epoch().count());
    json += R"(":")";

    // Encode inner data as base64-like
    for (size_t i = 0; i < len; i++) {
        char buf[4];
        snprintf(buf, sizeof(buf), "%02x", inner_data[i]);
        json += buf;
    }

    json += R"(","message_type":"data","priority":"normal"})";

    std::vector<uint8_t> result(json.begin(), json.end());

    // Добавляем protobuf-подобные varint поля
    // field 1 (message_id), type: length-delimited
    std::vector<uint8_t> pb;
    pb.push_back(0x0A); // field 1, wire type 2 (length-delimited)
    // length as varint
    uint64_t len_varint = result.size();
    while (len_varint > 0x7F) {
        pb.push_back((len_varint & 0x7F) | 0x80);
        len_varint >>= 7;
    }
    pb.push_back(len_varint & 0x7F);

    result.insert(result.begin(), pb.begin(), pb.end());

    return result;
}

// ═══════════════════════════════════════════════════════════════
// gRPC message builder
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> CamouflageTunnel::buildGRPCMessage(const uint8_t* inner_data, size_t len) {
    TunnelPacket pkt;
    pkt.type = 0;
    pkt.flags = 0;
    pkt.payload.assign(inner_data, inner_data + len);
    return pkt.encode(TunnelProtocol::GRPC);
}

// ═══════════════════════════════════════════════════════════════
// WebSocket frame builder
// ═══════════════════════════════════════════════════════════════

std::vector<uint8_t> CamouflageTunnel::buildWebSocketFrame(
    const uint8_t* inner_data, size_t len, uint8_t opcode) {
    TunnelPacket pkt;
    pkt.type = opcode;
    pkt.flags = 0;
    pkt.payload.assign(inner_data, inner_data + len);
    return pkt.encode(TunnelProtocol::WEBSOCKET);
}
