// ═══════════════════════════════════════════════════════════════
// NEXUSGram — MTProto Native Header
// ═══════════════════════════════════════════════════════════════

#pragma once

#include <cstdint>
#include <vector>
#include <string>

// TL serialization (как в Telegram для Android)
class NativeByteBuffer {
public:
    NativeByteBuffer();
    explicit NativeByteBuffer(const std::vector<uint8_t>& data);

    void writeInt32(int32_t v);
    void writeInt64(int64_t v);
    void writeDouble(double v);
    void writeBytes(const uint8_t* data, size_t len);
    void writeString(const std::string& s);
    void writeByte(uint8_t b);
    void writeBool(bool v);
    void writeInt32Vector(const std::vector<int32_t>& vec);

    int32_t readInt32();
    int64_t readInt64();
    std::string readString();
    void readBytes(uint8_t* out, size_t len);

    size_t position() const;
    size_t remaining() const;
    const uint8_t* data() const;
    size_t size() const;
    std::vector<uint8_t> getData() const;

private:
    std::vector<uint8_t> _data;
    size_t _pos;
};

// AES-IGE для MTProto 2.0
class AesIge {
public:
    static void encrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv);
    static void decrypt(const uint8_t* input, uint8_t* output, size_t len,
                        const uint8_t* key, const uint8_t* iv);
};

// MTProto Client через SOCKS5
class MtprotoClient {
public:
    MtprotoClient();
    ~MtprotoClient();

    bool connect(const std::string& proxy_host, int proxy_port,
                 const std::string& dc_host, int dc_port);
    void disconnect();
    bool sendTLMessage(const std::vector<uint8_t>& tl_data);
    std::vector<uint8_t> receive(int timeout_ms = 10000);
    bool isConnected() const;
};

// Ghost Mode (AyuGram features)
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
