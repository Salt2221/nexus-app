// ═══════════════════════════════════════════════════════════════
// NEXUSGram — MTProto Native Header
// ═══════════════════════════════════════════════════════════════

#pragma once

#include <cstdint>
#include <vector>
#include <string>
#include <cstring>
#include <algorithm>

// ═══════════════════════════════════════════════════════════════
// TL Serialization — как в Telegram для Android
// ═══════════════════════════════════════════════════════════════

class NativeByteBuffer {
public:
    NativeByteBuffer() : _pos(0) {}
    explicit NativeByteBuffer(const std::vector<uint8_t>& data) : _data(data), _pos(0) {}
    NativeByteBuffer(const uint8_t* data, size_t len) : _data(data, data + len), _pos(0) {}

    void writeInt32(int32_t v) {
        v = __builtin_bswap32(v);
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
        writeInt64((int64_t)bits);
    }

    void writeBytes(const uint8_t* data, size_t len) {
        append(data, len);
    }

    void writeString(const std::string& s) {
        size_t len = s.length();
        if (len < 254) {
            writeByte((uint8_t)len);
            writeBytes((const uint8_t*)s.data(), len);
            size_t pad = (len + 1) % 4;
            if (pad > 0)
                for (size_t i = 0; i < 4 - pad; i++) writeByte(0);
        } else {
            writeByte(254);
            writeByte((uint8_t)(len & 0xFF));
            writeByte((uint8_t)((len >> 8) & 0xFF));
            writeByte((uint8_t)((len >> 16) & 0xFF));
            writeBytes((const uint8_t*)s.data(), len);
            size_t pad = len % 4;
            if (pad > 0)
                for (size_t i = 0; i < 4 - pad; i++) writeByte(0);
        }
    }

    void writeByte(uint8_t b) { _data.push_back(b); }

    void writeBool(bool v) {
        writeInt32(v ? 0x997275b5 : 0xbc799737);
    }

    void writeInt32Vector(const std::vector<int32_t>& vec) {
        writeInt32(0x1cb5c415);
        writeInt32((int32_t)vec.size());
        for (auto v : vec) writeInt32(v);
    }

    int32_t readInt32() {
        if (_pos + 4 > _data.size()) return 0;
        int32_t v;
        memcpy(&v, &_data[_pos], 4);
        _pos += 4;
        return (int32_t)__builtin_bswap32((uint32_t)v);
    }

    int64_t readInt64() {
        if (_pos + 8 > _data.size()) return 0;
        uint32_t low = (uint32_t)readInt32();
        uint32_t high = (uint32_t)readInt32();
        return ((int64_t)high << 32) | low;
    }

    std::string readString() {
        if (_pos >= _data.size()) return "";
        uint8_t first = _data[_pos++];
        size_t len;
        if (first < 254) {
            len = first;
        } else {
            if (_pos + 3 > _data.size()) return "";
            len = _data[_pos] | (_data[_pos+1] << 8) | (_data[_pos+2] << 16);
            _pos += 3;
        }
        if (_pos + len > _data.size()) return "";
        std::string result((const char*)&_data[_pos], len);
        _pos += len;
        size_t aligned = (len + (first < 254 ? 1 : 4)) % 4;
        if (aligned > 0) _pos += 4 - aligned;
        return result;
    }

    void readBytes(uint8_t* out, size_t len) {
        if (_pos + len > _data.size()) return;
        memcpy(out, &_data[_pos], len);
        _pos += len;
    }

    size_t position() const { return _pos; }
    size_t remaining() const { return _data.size() - _pos; }
    const uint8_t* data() const { return _data.data(); }
    size_t size() const { return _data.size(); }
    std::vector<uint8_t> getData() const { return _data; }

private:
    std::vector<uint8_t> _data;
    size_t _pos;

    void append(const uint8_t* buf, size_t len) {
        _data.insert(_data.end(), buf, buf + len);
    }
};

// ═══════════════════════════════════════════════════════════════
// AES-IGE для MTProto 2.0
// ═══════════════════════════════════════════════════════════════

class AesIge {
public:
    static void encrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv);
    static void decrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv);
};

// ═══════════════════════════════════════════════════════════════
// MTProto Client через SOCKS5
// ═══════════════════════════════════════════════════════════════

class MtprotoClient {
public:
    MtprotoClient() : _sock(-1), _seq_no(0), _connected(false), _dc_id(2) {}
    ~MtprotoClient() { disconnect(); }

    bool connect(const std::string& proxy_host, int proxy_port,
                 const std::string& dc_host, int dc_port);
    void disconnect();
    bool sendTLMessage(const std::vector<uint8_t>& tl_data);
    std::vector<uint8_t> receive(int timeout_ms = 10000);
    bool isConnected() const { return _connected; }

private:
    int _sock;
    int _seq_no;
    bool _connected;
    std::string _dc_host;
    int _dc_port;
    int _dc_id;

    bool _socks5Connect(const std::string& proxy_host, int proxy_port,
                        const std::string& target_host, int target_port);
    ssize_t recvAll(uint8_t* buf, size_t len);
};

// ═══════════════════════════════════════════════════════════════
// Ghost Mode (AyuGram features)
// ═══════════════════════════════════════════════════════════════

class GhostMode {
public:
    bool enabled = false;
    bool hideTyping = true;
    bool hideOnline = true;
    bool hideReadReceipts = true;
    bool antiRecall = true;
    bool localPremium = false;

    void applyToTL(NativeByteBuffer& buffer);
};
