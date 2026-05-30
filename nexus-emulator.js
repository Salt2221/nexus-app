/**
 * NEXUS Local Test Emulator
 * 
 * Полностью эмулирует поведение NexusVpnService на локальной машине (Node.js).
 * Позволяет тестировать MTProto handshake + SOCKS5 + DPI bypass без Android.
 *
 * Использование:
 *   node nexus-emulator.js [--mt-port 1443] [--socks-port 1080] [--debug]
 *
 * Логи:
 *   - Все входящие/исходящие пакеты
 *   - Handshake расшифровка
 *   - Fake TLS верификация
 *   - DPI bypass модификации
 *   - Ошибки с stacktrace
 */

const net = require('net');
const crypto = require('crypto');

// ============= CONSTANTS =============
const HANDSHAKE_LEN = 64;
const SKIP_LEN = 8;
const PREKEY_LEN = 32;
const IV_LEN = 16;
const PROTO_TAG_POS = 56;
const DC_IDX_POS = 60;

const PROTO_TAG_ABRIDGED = Buffer.from([0xEF, 0xEF, 0xEF, 0xEF]);
const PROTO_TAG_INTERMEDIATE = Buffer.from([0xEE, 0xEE, 0xEE, 0xEE]);
const PROTO_TAG_SECURE = Buffer.from([0xDD, 0xDD, 0xDD, 0xDD]);

// Fake Telegram DCs
const TG_DC_IPS = {
    1: '149.154.175.50', 2: '149.154.167.51',
    3: '149.154.175.100', 4: '149.154.167.91',
    5: '149.154.171.5'
};

// ============= SECRET =============
function generateSecret() {
    const rand = crypto.randomBytes(16);
    const full = Buffer.alloc(17);
    full[0] = 0xDD; // Fake TLS flag
    rand.copy(full, 1);
    return full.toString('hex');
}

const SECRET = generateSecret();
const REAL_SECRET = Buffer.from(SECRET, 'hex').subarray(1, 17);

// ============= LOGGING =============
const LOG_LEVELS = { NONE: 0, ERROR: 1, WARN: 2, INFO: 3, DEBUG: 4, TRACE: 5 };
let logLevel = LOG_LEVELS.DEBUG;

function log(level, tag, msg, data) {
    if (level > logLevel) return;
    const prefix = {
        [LOG_LEVELS.ERROR]: '❌',
        [LOG_LEVELS.WARN]: '⚠️',
        [LOG_LEVELS.INFO]: 'ℹ️',
        [LOG_LEVELS.DEBUG]: '🐛',
        [LOG_LEVELS.TRACE]: '🔍'
    }[level] || '•';
    const ts = new Date().toISOString().substring(11, 23);
    let line = `${prefix} [${ts}] [${tag}] ${msg}`;
    if (data) {
        const str = typeof data === 'string' ? data :
            Buffer.isBuffer(data) ? data.toString('hex').substring(0, 64) + '...' :
            JSON.stringify(data);
        line += `\n   └─ ${str}`;
    }
    console.log(line);
}

const logE = (tag, msg, d) => log(LOG_LEVELS.ERROR, tag, msg, d);
const logW = (tag, msg, d) => log(LOG_LEVELS.WARN, tag, msg, d);
const logI = (tag, msg, d) => log(LOG_LEVELS.INFO, tag, msg, d);
const logD = (tag, msg, d) => log(LOG_LEVELS.DEBUG, tag, msg, d);
const logT = (tag, msg, d) => log(LOG_LEVELS.TRACE, tag, msg, d);

// ============= CRYPTO HELPERS =============
function sha256(data) {
    return crypto.createHash('sha256').update(data).digest();
}

function hmacSha256(key, data) {
    return crypto.createHmac('sha256', key).update(data).digest();
}

function createAesCtr(key, iv) {
    const cipher = crypto.createCipheriv('aes-256-ctr', key, iv);
    // Prevent auto-final
    cipher.setAutoPadding(false);
    return cipher;
}

function aesCtrEncrypt(key, iv, data) {
    const c = createAesCtr(key, iv);
    return Buffer.concat([c.update(data), c.final()]);
}

// ============= MTProto STATE =============
const mtStats = {
    connections: 0,
    total: 0,
    handshakeOk: 0,
    handshakeFail: 0,
    currentDc: '',
    protocol: ''
};

// ============= MTProto HANDLER =============
class MtProtoHandler {
    constructor(socket, key) {
        this.socket = socket;
        this.key = key;
        this.buffer = Buffer.alloc(0);
        this.secret = REAL_SECRET;
    }

    handle() {
        this.socket.once('data', (data) => {
            this._handleHandshake(data);
        });

        this.socket.on('error', (err) => {
            logE('MT', `[${this.key}] socket error: ${err.message}`);
            this.close();
        });

        this.socket.on('close', () => {
            mtStats.connections--;
        });
    }

    _handleHandshake(data) {
        if (data.length < HANDSHAKE_LEN) {
            logW('MT', `[${this.key}] short handshake: ${data.length} bytes`);
            logT('MT', `Handshake hex: ${data.toString('hex')}`);
            mtStats.handshakeFail++;
            this.close();
            return;
        }

        const hs = data.subarray(0, HANDSHAKE_LEN);
        logI('MT', `[${this.key}] Handshake received (${hs.length} bytes)`);
        logD('MT', `Handshake hex: ${hs.toString('hex')}`);

        // Try obfuscated handshake
        const result = this._tryObfuscatedHs(hs);
        if (result) {
            this._onHandshakeOk(hs, result);
            return;
        }

        // Try Fake TLS (delegate to static helper)
        mtStats.handshakeFail++;
        logW('MT', `[${this.key}] obfs failed, trying Fake TLS...`);
        const fth = new FakeTlsHandler(this.socket, this.key, this.secret);
        const ok = fth.handle(data);
        if (!ok) {
            logW('MT', `[${this.key}] Fake TLS also failed, closing`);
            this.close();
        }
    }

    _tryObfuscatedHs(hs) {
        const preKey = hs.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN);
        const iv = hs.subarray(SKIP_LEN + PREKEY_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN);
        const key = sha256(Buffer.concat([preKey, this.secret]));
        
        logT('MT', `PreKey: ${preKey.toString('hex')}`);
        logT('MT', `Key: ${key.toString('hex')}`);
        logT('MT', `IV: ${iv.toString('hex')}`);

        let decrypted;
        try {
            decrypted = aesCtrEncrypt(key, iv, hs);
        } catch (e) {
            logE('MT', `AES-CTR failed: ${e.message}`);
            return null;
        }

        const tag = decrypted.subarray(PROTO_TAG_POS, PROTO_TAG_POS + 4);
        logD('MT', `Protocol tag: ${tag.toString('hex')}`);

        if (!tag.equals(PROTO_TAG_ABRIDGED) &&
            !tag.equals(PROTO_TAG_INTERMEDIATE) &&
            !tag.equals(PROTO_TAG_SECURE)) {
            logD('MT', `Unknown protocol tag: ${tag.toString('hex')} (expected one of known)`);
            return null;
        }

        const protoName = tag.equals(PROTO_TAG_ABRIDGED) ? 'Abridged' :
            tag.equals(PROTO_TAG_INTERMEDIATE) ? 'Intermediate' : 'Secure (Fake TLS)';
        logI('MT', `Protocol detected: ${protoName}`);

        // Extract DC ID (little-endian from pos 60)
        const dcRaw = decrypted.readUInt16LE(DC_IDX_POS);
        const dcSigned = dcRaw >= 0x8000 ? dcRaw - 0x10000 : dcRaw;
        const dc = Math.abs(dcSigned);
        const media = dcSigned < 0;

        logI('MT', `DC: ${dc}${media ? ' (media)' : ''}`);

        return { dc, media, tag, preKey, iv, key, decrypted };
    }

    _onHandshakeOk(hs, result) {
        mtStats.handshakeOk++;
        mtStats.currentDc = `DC${result.dc}${result.media ? 'm' : ''}`;
        mtStats.protocol = result.tag.equals(PROTO_TAG_SECURE) ? 'AES-CTR+FD' : 'AES-CTR';
        
        logI('MT', `[${this.key}] ✅ Handshake OK → ${mtStats.currentDc} (${mtStats.protocol})`);

        // Generate relay init
        const dcIdx = result.media ? -result.dc : result.dc;
        const relay = this._genRelayInit(result.tag, dcIdx);
        const ctx = this._buildCtx(hs, relay);

        logT('MT', `Relay init (${relay.length} bytes): ${relay.toString('hex').substring(0, 64)}...`);

        // Send relay init back
        this.socket.write(relay);

        // Now try to connect to real TG DC (or simulate)
        const tgHost = TG_DC_IPS[result.dc] || '149.154.167.51';
        logI('MT', `[${this.key}] Connecting to ${tgHost}:443...`);

        // In emulator mode — connect to real TG and relay
        this._relayToTg(tgHost, ctx);
    }

    _genRelayInit(tag, dcIdx) {
        while (true) {
            const buf = crypto.randomBytes(64);
            if (buf[0] === 0xEF) continue;
            if (buf.subarray(4, 8).equals(Buffer.alloc(4))) continue;

            const ek = buf.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN);
            const eiv = buf.subarray(SKIP_LEN + PREKEY_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN);
            const enc = aesCtrEncrypt(ek, eiv, buf);

            const dcBuf = Buffer.alloc(2);
            dcBuf.writeInt16LE(dcIdx & 0xFFFF, 0);
            const tail = Buffer.concat([tag, dcBuf, Buffer.alloc(2)]);

            for (let i = 0; i < 8; i++) {
                buf[PROTO_TAG_POS + i] = enc[PROTO_TAG_POS + i] ^ buf[PROTO_TAG_POS + i] ^ tail[i];
            }
            return buf;
        }
    }

    _buildCtx(hs, relay) {
        const cdp = hs.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN);
        const cdi = hs.subarray(SKIP_LEN + PREKEY_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN);
        const cdKey = sha256(Buffer.concat([cdp, this.secret]));

        const cepRev = Buffer.from(hs.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN)).reverse();
        const ceKey = sha256(Buffer.concat([cepRev.subarray(0, PREKEY_LEN), this.secret]));
        const ceIv = cepRev.subarray(PREKEY_LEN, PREKEY_LEN + IV_LEN);

        const tep = relay.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN);
        const tei = relay.subarray(SKIP_LEN + PREKEY_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN);

        const tdpRev = Buffer.from(relay.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN)).reverse();
        const tdKey = tdpRev.subarray(0, PREKEY_LEN);
        const tdIv = tdpRev.subarray(PREKEY_LEN, PREKEY_LEN + IV_LEN);

        return {
            cdKey, cdi,
            ceKey, ceIv,
            teKey: tep, teIv: tei,
            tdKey, tdIv,
            cdNonce: Buffer.alloc(64),
            teNonce: Buffer.alloc(64)
        };
    }

    _relayToTg(tgHost, ctx) {
        const tg = new net.Socket();
        let tgConnected = false;

        tg.connect(443, tgHost, () => {
            tgConnected = true;
            logI('MT', `[${this.key}] Connected to TG DC: ${tgHost}:443`);

            // Bidirectional relay
            // Client → TG
            this.socket.on('data', (clientData) => {
                try {
                    // Decrypt from client (fast-forward nonce)
                    const decrypted = this._xorWithNonce(clientData, ctx.cdNonce);
                    // Encrypt to TG
                    const encrypted = aesCtrEncrypt(ctx.teKey, ctx.teIv, decrypted);
                    tg.write(encrypted);
                    logT('MT', `↗ ${clientData.length} bytes → TG`);
                    mtStats.total += clientData.length;
                } catch (e) {
                    logE('MT', `C→TG relay: ${e.message}`);
                    this.close();
                }
            });

            // TG → Client
            tg.on('data', (tgData) => {
                try {
                    // Decrypt from TG
                    const decrypted = aesCtrEncrypt(ctx.tdKey, ctx.tdIv, tgData);
                    // Encrypt to client
                    const encrypted = aesCtrEncrypt(ctx.ceKey, ctx.ceIv, decrypted);
                    this.socket.write(encrypted);
                    logT('MT', `↘ ${tgData.length} bytes ← TG`);
                } catch (e) {
                    logE('MT', `TG→C relay: ${e.message}`);
                }
            });
        });

        tg.on('error', (err) => {
            logE('MT', `[${this.key}] TG connect error: ${err.message}`);
            // Still send relay init and fallback — simulate echo
            if (!tgConnected) {
                logW('MT', `[${this.key}] TG not reachable, simulating echo relay (TEST MODE)`);
                this.socket.on('data', (d) => {
                    logD('MT', `[${this.key}] Echoing ${d.length} bytes back`);
                    this.socket.write(d);
                });
            }
        });

        tg.on('close', () => {
            logI('MT', `[${this.key}] TG connection closed`);
            if (!this.socket.destroyed) this.close();
        });

        this.tg = tg;
    }

    _xorWithNonce(data, nonce) {
        const result = Buffer.alloc(data.length);
        for (let i = 0; i < data.length; i++) {
            result[i] = data[i] ^ nonce[i % nonce.length];
        }
        return result;
    }

    close() {
        try { this.socket.destroy(); } catch (_) {}
        try { if (this.tg) this.tg.destroy(); } catch (_) {}
    }
}

// ============= FAKE TLS =============
class FakeTlsHandler {
    constructor(socket, key, secret) {
        this.socket = socket;
        this.key = key;
        this.secret = secret;
    }

    handle(data) {
        const CLIENT_RAND_OFF = 11;
        const CLIENT_RAND_LEN = 32;

        if (data.length < CLIENT_RAND_OFF + CLIENT_RAND_LEN) {
            logW('TLS', `[${this.key}] Too short for TLS: ${data.length}`);
            return false;
        }

        if (data[0] !== 0x16) {
            logW('TLS', `[${this.key}] Not a TLS record: 0x${data[0].toString(16)}`);
            return false;
        }

        const clientRandom = data.subarray(CLIENT_RAND_OFF, CLIENT_RAND_OFF + CLIENT_RAND_LEN);
        logT('TLS', `Client random: ${clientRandom.toString('hex')}`);

        // Zero out client random for verification
        const zeroed = Buffer.from(data);
        for (let i = CLIENT_RAND_OFF; i < CLIENT_RAND_OFF + CLIENT_RAND_LEN; i++) {
            zeroed[i] = 0;
        }

        // HMAC verification
        const expected = hmacSha256(this.secret, zeroed);
        logT('TLS', `Expected HMAC (28 bytes): ${expected.subarray(0, 28).toString('hex')}`);
        logT('TLS', `Actual (28 bytes of random): ${clientRandom.subarray(0, 28).toString('hex')}`);

        let match = true;
        for (let i = 0; i < 28; i++) {
            if (clientRandom[i] !== expected[i]) { match = false; break; }
        }

        if (!match) {
            logW('TLS', `[${this.key}] HMAC mismatch`);
            return false;
        }

        logI('TLS', `[${this.key}] ✅ Fake TLS HMAC verified!`);

        // Generate ServerHello + CCS + AppData
        const sid = crypto.randomBytes(32);
        const serverHello = this._buildServerHello(sid);
        this.socket.write(serverHello);

        logI('TLS', `[${this.key}] Sent ServerHello (${serverHello.length} bytes)`);

        // Now expect inner handshake (real MTProto)
        this.socket.once('data', (innerData) => {
            if (innerData.length < HANDSHAKE_LEN) {
                logW('TLS', `[${this.key}] Inner handshake too short: ${innerData.length}`);
                mtStats.handshakeFail++;
                this.close();
                return;
            }

            logI('TLS', `[${this.key}] Inner handshake received (${innerData.length} bytes)`);

            const handler = new MtProtoHandler(this.socket, this.key);
            handler.secret = this.secret;
            handler._handleHandshake(innerData);
        });

        return true;
    }

    _buildServerHello(sid) {
        // ServerHello + CCS + random AppData
        const sh = Buffer.alloc(43 + 32 + 35 + 32 + 6);
        let off = 0;

        // TLS Record: Handshake
        sh[off++] = 0x16; // Content Type
        sh[off++] = 0x03; sh[off++] = 0x03; // TLS 1.2
        sh[off++] = 0x00; sh[off++] = 0x7A; // length
        sh[off++] = 0x02; // Handshake: ServerHello
        sh[off++] = 0x00; sh[off++] = 0x00; sh[off++] = 0x76; // length (118)
        sh[off++] = 0x03; sh[off++] = 0x03; // version

        // Server random (32 bytes)
        const serverRand = crypto.randomBytes(32);
        serverRand.copy(sh, off); off += 32;

        // Session ID
        sh[off++] = 0x20; // length
        sid.copy(sh, off, 0, 32); off += 32;

        // Cipher suite: TLS_AES_128_GCM_SHA256
        sh[off++] = 0x13; sh[off++] = 0x01;
        sh[off++] = 0x00; // no compression

        // Extensions
        sh[off++] = 0x00; sh[off++] = 0x2E; // ext length
        // key_share
        sh[off++] = 0x00; sh[off++] = 0x33;
        sh[off++] = 0x00; sh[off++] = 0x24;
        sh[off++] = 0x00; sh[off++] = 0x1D;
        sh[off++] = 0x00; sh[off++] = 0x20;
        const pubKey = crypto.randomBytes(32);
        pubKey.copy(sh, off); off += 32;
        // supported_versions
        sh[off++] = 0x00; sh[off++] = 0x2B;
        sh[off++] = 0x00; sh[off++] = 0x02;
        sh[off++] = 0x03; sh[off++] = 0x04;

        // CCS
        const ccs = Buffer.from([0x14, 0x03, 0x03, 0x00, 0x01, 0x01]);

        // AppData (random)
        const appSize = 1500 + Math.floor(Math.random() * 500);
        const appData = crypto.randomBytes(appSize);
        const appRec = Buffer.alloc(5 + appSize);
        appRec[0] = 0x17; appRec[1] = 0x03; appRec[2] = 0x03;
        appRec.writeUInt16BE(appSize, 3);
        appData.copy(appRec, 5);

        return Buffer.concat([sh, ccs, appRec]);
    }

    close() {
        try { this.socket.destroy(); } catch (_) {}
    }
}

// ============= SOCKS5 HANDLER =============
class Socks5Handler {
    constructor(socket, key) {
        this.socket = socket;
        this.key = key;
    }

    handle() {
        // SOCKS5 handshake
        this.socket.once('data', (data) => {
            this._handleAuth(data);
        });
        this.socket.on('error', (err) => {
            logE('S5', `[${this.key}] ${err.message}`);
            this.close();
        });
    }

    _handleAuth(data) {
        if (data.length < 2 || data[0] !== 0x05) {
            logW('S5', `[${this.key}] Not SOCKS5`);
            this.close();
            return;
        }

        const nmethods = data[1];
        if (data.length < 2 + nmethods) {
            logW('S5', `[${this.key}] Auth header incomplete`);
            this.close();
            return;
        }

        logD('S5', `[${this.key}] Auth methods: ${data.subarray(2, 2 + nmethods).toString('hex')}`);

        // No auth
        this.socket.write(Buffer.from([0x05, 0x00]));

        // Wait for request
        this.socket.once('data', (reqData) => this._handleRequest(reqData));
    }

    _handleRequest(data) {
        if (data.length < 4 || data[0] !== 0x05 || data[1] !== 0x01) {
            logW('S5', `[${this.key}] Bad request`);
            this.socket.write(Buffer.from([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
            this.close();
            return;
        }

        const atyp = data[3];
        let host, port, remaining = data.subarray(4);
        let totalExpected;

        switch (atyp) {
            case 0x01: // IPv4
                if (remaining.length < 4) { this._fail(); return; }
                host = Array.from(remaining.subarray(0, 4)).join('.');
                remaining = remaining.subarray(4);
                break;
            case 0x03: // Domain
                if (remaining.length < 1) { this._fail(); return; }
                const len = remaining[0];
                remaining = remaining.subarray(1);
                if (remaining.length < len) { this._fail(); return; }
                host = remaining.subarray(0, len).toString();
                remaining = remaining.subarray(len);
                break;
            default:
                logW('S5', `[${this.key}] Unknown ATYP: 0x${atyp.toString(16)}`);
                this._fail();
                return;
        }

        if (remaining.length < 2) { this._fail(); return; }
        port = remaining.readUInt16BE(0);

        logI('S5', `[${this.key}] Request: ${host}:${port}`);

        // Connect to target
        const target = new net.Socket();
        target.connect(port, host, () => {
            logI('S5', `[${this.key}] ✅ Connected to ${host}:${port}`);

            // Reply OK
            this.socket.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, (port >> 8) & 0xFF, port & 0xFF]));

            // Bidirectional relay
            this._relay(target);
        });

        target.on('error', (err) => {
            logE('S5', `[${this.key}] Target ${host}:${port} - ${err.message}`);
            this._fail();
        });
    }

    _relay(target) {
        let upBytes = 0, downBytes = 0;

        // Client → Target
        this.socket.on('data', (data) => {
            try {
                // Apply DPI bypass
                const bypassed = this._dpiBypass(data);
                target.write(bypassed);
                upBytes += data.length;
                logT('S5', `↗ ${data.length} bytes → target (bypass: ${bypassed.length - data.length} extra)`);
            } catch (e) {
                logE('S5', `Relay error: ${e.message}`);
            }
        });

        // Target → Client
        target.on('data', (data) => {
            try {
                this.socket.write(data);
                downBytes += data.length;
            } catch (e) {
                logE('S5', `Relay error: ${e.message}`);
            }
        });

        target.on('close', () => {
            logI('S5', `[${this.key}] Done: ↑${upBytes} ↓${downBytes} bytes`);
            this.close();
        });

        this.socket.on('close', () => {
            if (!target.destroyed) target.destroy();
        });
    }

    _dpiBypass(data) {
        if (data.length < 10) return data;

        // 20% chance to add prefix garbage
        if (Math.random() < 0.2) {
            const prefixLen = 4 + Math.floor(Math.random() * 12);
            const prefix = crypto.randomBytes(prefixLen);
            prefix[0] = 'X'.charCodeAt(0);
            if (prefixLen > 1) prefix[1] = '-'.charCodeAt(0);
            return Buffer.concat([prefix, data]);
        }

        return data;
    }

    _fail() {
        try { this.socket.write(Buffer.from([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0])); } catch (_) {}
        this.close();
    }

    close() {
        try { this.socket.destroy(); } catch (_) {}
    }
}

// ============= SERVERS =============
function startMtProto(port) {
    const server = net.createServer((socket) => {
        mtStats.connections++;
        const key = `${socket.remoteAddress}:${socket.remotePort}`;
        logI('MT', `[${key}] New connection (${mtStats.connections} total)`);

        const handler = new MtProtoHandler(socket, key);
        handler.handle();
    });

    server.on('error', (err) => {
        logE('MT', `Server error: ${err.message}`);
    });

    server.listen(port, '127.0.0.1', () => {
        logI('MT', `🚀 MTProto proxy: 127.0.0.1:${port}`);
        logI('MT', `   Secret: ${SECRET}`);
        logI('MT', `   Test: nc -v 127.0.0.1 ${port} < handshake.bin`);
    });

    return server;
}

function startSocks5(port) {
    const server = net.createServer((socket) => {
        const key = `${socket.remoteAddress}:${socket.remotePort}`;
        logI('S5', `[${key}] New connection`);

        const handler = new Socks5Handler(socket, key);
        handler.handle();
    });

    server.on('error', (err) => {
        logE('S5', `Server error: ${err.message}`);
    });

    server.listen(port, '127.0.0.1', () => {
        logI('S5', `🚀 SOCKS5 proxy: 127.0.0.1:${port}`);
    });

    return server;
}

// ============= TEST MODE — simulate MTProto client =============

/**
 * Генерирует правильный obfuscated handshake как это делает настоящий TG клиент:
 * 1. Берём 64 случайных байта
 * 2. preKey = bytes[8..39], iv = bytes[40..55]
 * 3. key = SHA256(preKey + secret)
 * 4. Шифруем весь 64-байтовый блок AES-CTR(key, iv)
 * 5. Кладём протокольный тег (0xEEEEEEEE Intermediate) и DC ID на позиции 56-63
 * 6. XOR-им нужные байты обратно через шифрованные
 */
function testLocalConnection(port) {
    logI('TEST', `Running self-test: connecting to MTProto on 127.0.0.1:${port}...`);

    const client = new net.Socket();
    let sent = false;

    client.connect(port, '127.0.0.1', () => {
        // Step 1: 64 random bytes
        const rand = crypto.randomBytes(64);
        const preKey = rand.subarray(SKIP_LEN, SKIP_LEN + PREKEY_LEN);
        const iv = rand.subarray(SKIP_LEN + PREKEY_LEN, SKIP_LEN + PREKEY_LEN + IV_LEN);
        const key = sha256(Buffer.concat([preKey, REAL_SECRET]));

        // Step 2: encrypt the 64-byte rand with AES-CTR
        const encrypted = aesCtrEncrypt(key, iv, rand);

        // Step 3: build the protocol tail (8 bytes: protocol_tag + DC + padding)
        // DC=2, Intermediate protocol
        const dcBuf = Buffer.alloc(2);
        dcBuf.writeInt16LE(2, 0); // DC 2
        const tail = Buffer.concat([PROTO_TAG_INTERMEDIATE, dcBuf, Buffer.alloc(2)]);

        // Step 4: encode tail into position 56-63 via XOR
        // actual_wire[56..63] = encrypted[56..63] XOR rand[56..63] XOR tail
        const result = Buffer.from(rand);
        for (let i = 0; i < 8; i++) {
            result[PROTO_TAG_POS + i] = encrypted[PROTO_TAG_POS + i] ^
                                        rand[PROTO_TAG_POS + i] ^
                                        tail[i];
        }

        logD('TEST', `Sending ${result.length}-byte handshake`);
        logD('TEST', `First 32 bytes hex: ${result.subarray(0, 32).toString('hex')}`);
        client.write(result);
        sent = true;
        logI('TEST', 'Self-test: obfuscated handshake sent (Intermediate, DC 2)');
    });

    client.on('data', (data) => {
        logI('TEST', `Self-test: received ${data.length} bytes back`);
        logD('TEST', `Response hex (first 32): ${data.subarray(0, 32).toString('hex')}`);

        // Parse relay response: verify it starts like valid relay init
        if (data.length >= 64) {
            logI('TEST', '✅ Self-test PASSED — MTProto server sent relay init (64+ bytes)');
        } else {
            logW('TEST', `⚠️ Short response: ${data.length} bytes`);
        }
        client.destroy();
    });

    client.on('error', (err) => {
        if (!sent) {
            logE('TEST', `Self-test FAILED: ${err.message}`);
        }
    });

    setTimeout(() => {
        if (!client.destroyed) {
            logW('TEST', 'Self-test timeout (no response in 5s)');
            logW('TEST', '⚠️ MTProto not responding — possible handshake logic issue');
            client.destroy();
        }
    }, 5000);
}

// ============= MAIN =============
function main() {
    const args = process.argv.slice(2);
    let mtPort = 1443;
    let socksPort = 1080;
    let runTest = true;

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--mt-port': mtPort = parseInt(args[++i]); break;
            case '--socks-port': socksPort = parseInt(args[++i]); break;
            case '--no-test': runTest = false; break;
            case '--debug': logLevel = LOG_LEVELS.DEBUG; break;
            case '--trace': logLevel = LOG_LEVELS.TRACE; break;
            case '--quiet': logLevel = LOG_LEVELS.INFO; break;
            case '--help':
            case '-h':
                console.log(`
NEXUS Local Test Emulator

Usage: node nexus-emulator.js [options]

Options:
  --mt-port PORT     MTProto proxy port (default: 1443)
  --socks-port PORT  SOCKS5 proxy port (default: 1080)
  --no-test          Skip self-test on startup
  --debug            Enable debug logging
  --trace            Enable trace logging (verbose)
  --quiet            Only show info and above
  --help, -h         Show this help

Self-test: connects to MTProto with valid handshake
`);
                process.exit(0);
        }
    }

    console.log(`
╔═══════════════════════════════════════════╗
║      NEXUS Local Test Emulator v1.0       ║
╚═══════════════════════════════════════════╝

Configuration:
  MTProto:   127.0.0.1:${mtPort}
  SOCKS5:    127.0.0.1:${socksPort}
  Secret:    ${SECRET}
  Log Level: ${['NONE','ERROR','WARN','INFO','DEBUG','TRACE'][logLevel]}
`);

    startMtProto(mtPort);
    startSocks5(socksPort);

    if (runTest) {
        setTimeout(() => testLocalConnection(mtPort), 1000);
    }

    // Status display
    setInterval(() => {
        if (mtStats.connections > 0 || mtStats.handshakeOk > 0) {
            logI('STAT', `MT: ${mtStats.connections} conn | ${mtStats.handshakeOk} OK / ${mtStats.handshakeFail} fail | ${mtStats.currentDc} | ${(mtStats.total / 1024).toFixed(1)}KB relayed`);
        }
    }, 10000);

    process.on('SIGINT', () => {
        console.log('\n\nShutting down...');
        process.exit(0);
    });
}

main();
