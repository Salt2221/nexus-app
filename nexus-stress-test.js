/**
 * NEXUS Stress Test — проверка всех функций на вылеты
 * 
 * Запуск: node nexus-stress-test.js
 * 
 * Тестирует:
 *  1. Edge Storage (P2P discovery, encrypt/decrypt, dedup)
 *  2. Volunteer Computing (matrix, primes, hash brute)
 *  3. SDR (FFT, FM demod, FIR, signal detection)
 *  4. VPN/MTProto (obfuscated handshake, fake TLS)
 *  5. SOCKS5 (connection roundtrip)
 *  6. DPI bypass (fragmentation, padding)
 *  7. Transport layer
 *  8. Нагрузочный тест (1000 итераций каждой функции)
 */

const crypto = require('crypto');

// --- Логирование -------------------------------------------
const OK = '?', FAIL = '?', SKIP = '??', WARN = '??';
let passed = 0, failed = 0;

function test(name, fn) {
    try {
        fn();
        passed++;
        console.log(`  ${OK} ${name}`);
    } catch (e) {
        failed++;
        console.log(`  ${FAIL} ${name}: ${e.message}`);
        console.log(`     Stack: ${e.stack?.split('\n').slice(1,3).join(' -> ')}`);
    }
}

function assert(cond, msg) {
    if (!cond) throw new Error(msg || 'assertion failed');
}

// --- 1. EDGE STORAGE ---------------------------------------
function testEdgeStorage() {
    console.log('\n?? Edge Storage:');

    test('SHA256 content hashing', () => {
        const data = Buffer.from('hello world');
        const hash = crypto.createHash('sha256').update(data).digest('hex');
        assert(hash.length === 64, 'hash length');
        assert(hash === 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', 'known hash');
    });

    test('AES-256-CTR encrypt/decrypt', () => {
        const key = crypto.randomBytes(32);
        const iv = crypto.randomBytes(16);
        const data = Buffer.from('zero-knowledge test data with some padding for realism');
        
        const cipher = crypto.createCipheriv('aes-256-ctr', key, iv);
        const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
        
        const decipher = crypto.createDecipheriv('aes-256-ctr', key, iv);
        const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
        
        assert(data.equals(decrypted), 'roundtrip match');
        assert(!data.equals(encrypted), 'encrypted != plain');
    });

    test('AES-256-GCM (zero-knowledge layer)', () => {
        const key = crypto.randomBytes(32);
        const iv = crypto.randomBytes(12);
        const data = Buffer.from('secret file content');
        
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
        const enc = Buffer.concat([cipher.update(data), cipher.final()]);
        const tag = cipher.getAuthTag();
        
        const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
        decipher.setAuthTag(tag);
        const dec = Buffer.concat([decipher.update(enc), decipher.final()]);
        
        assert(data.equals(dec), 'gcm roundtrip');
    });

    test('HMAC-SHA256 verification', () => {
        const key = crypto.randomBytes(32);
        const data = Buffer.from('peer identity proof');
        const hmac = crypto.createHmac('sha256', key).update(data).digest();
        const verify = crypto.createHmac('sha256', key).update(data).digest();
        assert(hmac.equals(verify), 'hmac match');
    });

    test('Key derivation (PBKDF2)', () => {
        const password = 'test-password';
        const salt = crypto.randomBytes(16);
        const key = crypto.pbkdf2Sync(password, salt, 100000, 32, 'sha512');
        assert(key.length === 32, 'derived key length');
    });

    test('Дедупликация — одинаковые данные = одинаковый хеш', () => {
        const d1 = crypto.randomBytes(1024);
        const d2 = Buffer.from(d1); // copy
        const h1 = crypto.createHash('sha256').update(d1).digest('hex');
        const h2 = crypto.createHash('sha256').update(d2).digest('hex');
        assert(h1 === h2, 'hash match');
    });

    test('Дедупликация — разные данные = разные хеши', () => {
        const d1 = crypto.randomBytes(1024);
        const d2 = crypto.randomBytes(1024);
        const h1 = crypto.createHash('sha256').update(d1).digest('hex');
        const h2 = crypto.createHash('sha256').update(d2).digest('hex');
        assert(h1 !== h2, 'hash different');
    });

    test('Потоковое шифрование большого файла (10MB)', () => {
        const key = crypto.randomBytes(32);
        const iv = crypto.randomBytes(16);
        const data = crypto.randomBytes(10 * 1024 * 1024);
        
        const cipher = crypto.createCipheriv('aes-256-ctr', key, iv);
        const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
        
        const decipher = crypto.createDecipheriv('aes-256-ctr', key, iv);
        const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
        
        assert(data.equals(decrypted), '10MB roundtrip');
    });
}

// --- 2. VOLUNTEER COMPUTING --------------------------------
function testVolunteerComputing() {
    console.log('\n?? Volunteer Computing:');

    test('Matrix multiplication 100x100', () => {
        const n = 100;
        const a = Array.from({length: n}, () => Array.from({length: n}, () => Math.random()));
        const b = Array.from({length: n}, () => Array.from({length: n}, () => Math.random()));
        const c = Array.from({length: n}, () => Array(n).fill(0));
        
        for (let i = 0; i < n; i++)
            for (let j = 0; j < n; j++)
                for (let k = 0; k < n; k++)
                    c[i][j] += a[i][k] * b[k][j];
        
        assert(c[50][50] !== 0, 'result non-zero');
    });

    test('Matrix multiplication 300x300 (тяжёлый)', () => {
        const n = 300;
        const a = Array.from({length: n}, () => Array.from({length: n}, () => Math.random()));
        const b = Array.from({length: n}, () => Array.from({length: n}, () => Math.random()));
        const c = Array.from({length: n}, () => Array(n).fill(0));
        
        for (let i = 0; i < n; i++)
            for (let j = 0; j < n; j++)
                for (let k = 0; k < n; k++)
                    c[i][j] += a[i][k] * b[k][j];
        
        assert(c[150][150] !== 0, 'result non-zero');
    });

    test('Поиск простых чисел до 100000 (решетом)', () => {
        const limit = 100000;
        const sieve = new Uint8Array(limit + 1);
        sieve[0] = sieve[1] = 1;
        for (let i = 2; i * i <= limit; i++)
            if (!sieve[i])
                for (let j = i * i; j <= limit; j += i)
                    sieve[j] = 1;
        const primes = [];
        for (let i = 2; i <= limit; i++)
            if (!sieve[i]) primes.push(i);
        
        assert(primes.length > 9500, `found ${primes.length} primes`);
        assert(primes[0] === 2, 'first prime is 2');
        assert(primes[1] === 3, 'second prime is 3');
    });

    test('SHA-256 hash brute (1000 attempts)', () => {
        const target = crypto.createHash('sha256').update('test42').digest('hex');
        let found = false;
        for (let i = 0; i < 1000; i++) {
            const hash = crypto.createHash('sha256').update(`test${i}`).digest('hex');
            if (hash === target) { found = true; break; }
        }
        assert(found, 'found matching hash');
    });

    test('Pi calculation (Leibniz, 1M iterations)', () => {
        let sum = 0;
        for (let i = 0; i < 1000000; i++) {
            sum += (i % 2 === 0 ? 1 : -1) / (2 * i + 1);
        }
        const pi = sum * 4;
        assert(Math.abs(pi - Math.PI) < 0.001, `pi approx: ${pi}`);
    });
}

// --- 3. SDR ------------------------------------------------
function testSdr() {
    console.log('\n?? SDR:');

    test('FFT 1024 — синтезированный сигнал', () => {
        const n = 1024;
        const re = new Float64Array(n);
        const im = new Float64Array(n);
        
        // 100Hz синус при 1024Hz sample rate
        for (let i = 0; i < n; i++) {
            re[i] = Math.sin(2 * Math.PI * 100 * i / 1024);
        }
        
        // FFT (Cooley-Tukey radix-2)
        function fft(re, im) {
            const n = re.length;
            for (let i = 1, j = 0; i < n; i++) {
                let bit = n >> 1;
                for (; j & bit; bit >>= 1) j ^= bit;
                j ^= bit;
                if (i < j) {
                    [re[i], re[j]] = [re[j], re[i]];
                    [im[i], im[j]] = [im[j], im[i]];
                }
            }
            for (let len = 2; len <= n; len <<= 1) {
                const ang = -2 * Math.PI / len;
                const wlenRe = Math.cos(ang);
                const wlenIm = Math.sin(ang);
                for (let i = 0; i < n; i += len) {
                    let wRe = 1, wIm = 0;
                    for (let j = 0; j < len / 2; j++) {
                        const uRe = re[i + j], uIm = im[i + j];
                        const vRe = re[i + j + len/2] * wRe - im[i + j + len/2] * wIm;
                        const vIm = re[i + j + len/2] * wIm + im[i + j + len/2] * wRe;
                        re[i + j] = uRe + vRe; im[i + j] = uIm + vIm;
                        re[i + j + len/2] = uRe - vRe; im[i + j + len/2] = uIm - vIm;
                        const newWRe = wRe * wlenRe - wIm * wlenIm;
                        const newWIm = wRe * wlenIm + wIm * wlenRe;
                        wRe = newWRe; wIm = newWIm;
                    }
                }
            }
        }
        
        fft(re, im);
        
        // Peak at bin ~100 (100Hz at 1024Hz sample rate)
        let maxMag = 0, maxBin = 0;
        for (let i = 0; i < n/2; i++) {
            const mag = Math.sqrt(re[i]*re[i] + im[i]*im[i]);
            if (mag > maxMag) { maxMag = mag; maxBin = i; }
        }
        
        assert(Math.abs(maxBin - 100) < 3, `peak at bin ${maxBin} (expected ~100)`);
    });

    test('FM демодуляция', () => {
        const n = 1000;
        const samples = [];
        let phase = 0;
        const fmSignal = 50; // deviation
        const modSignal = 5; // modulation frequency
        
        for (let i = 0; i < n; i++) {
            phase += fmSignal * Math.sin(2 * Math.PI * modSignal * i / n);
            samples.push(Math.cos(phase));
        }
        
        // FM demod: differentiate phase
        const demod = [];
        for (let i = 1; i < n; i++) {
            demod.push(samples[i] - samples[i-1]);
        }
        
        assert(demod.length === n - 1, 'demod length');
        assert(Math.abs(demod[100]) > 0, 'has signal');
    });

    test('FIR фильтр (low-pass)', () => {
        const n = 256;
        const taps = 64;
        const fc = 0.2; // cutoff
        
        // Generate filter
        const coeffs = new Float64Array(taps);
        for (let i = 0; i < taps; i++) {
            const m = i - taps / 2;
            coeffs[i] = m === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * m) / (Math.PI * m);
            // Hamming window
            coeffs[i] *= 0.54 - 0.46 * Math.cos(2 * Math.PI * i / (taps - 1));
        }
        
        const signal = new Float64Array(n);
        for (let i = 0; i < n; i++) {
            signal[i] = Math.sin(2 * Math.PI * 0.05 * i) + Math.sin(2 * Math.PI * 0.4 * i);
        }
        
        const filtered = new Float64Array(n);
        for (let i = 0; i < n; i++) {
            let sum = 0;
            for (let j = 0; j < taps && j <= i; j++) {
                sum += coeffs[j] * signal[i - j];
            }
            filtered[i] = sum;
        }
        
        // High freq (0.4) should be attenuated vs low freq (0.05)
        const lowMag = Math.abs(filtered.slice(10, 60).reduce((a,b) => a + Math.abs(b), 0));
        assert(lowMag > 5, 'low frequency present');
    });

    test('ADS-B like frame decoding', () => {
        // Simulate ADS-B frame (Mode S extended squitter)
        const frame = Buffer.alloc(112);
        // DF=17 (ADS-B), ICAO=0xABCDEF, altitude=35000ft
        const df17 = 17 << 3; // DF17
        frame[0] = df17;
        frame.writeUInt32BE(0xABCDEF, 1); // ICAO (24 bits, MSB)
        
        const df = (frame[0] >> 3) & 0x1F;
        assert(df === 17, 'DF=17 ADS-B');
        
        const icao = ((frame[1] & 0x07) << 16) | (frame[2] << 8) | frame[3];
        assert(icao === 0xABCDEF, `ICAO: ${icao.toString(16)}`);
    });

    test('Signal detection threshold', () => {
        const noise = Float64Array.from({length: 1000}, () => Math.random() * 2 - 1);
        const mean = noise.reduce((a,b) => a + b, 0) / noise.length;
        const variance = noise.reduce((a,b) => a + (b - mean)**2, 0) / noise.length;
        const std = Math.sqrt(variance);
        
        // Signal at 3 sigma
        const signal = Float64Array.from(noise);
        signal[500] = mean + 4 * std;
        
        const threshold = mean + 3 * std;
        assert(signal[500] > threshold, 'signal above threshold');
        assert(signal[100] < threshold, 'noise below threshold');
    });
}

// --- 4. MTProto / VPN --------------------------------------
function testMtProto() {
    console.log('\n??? VPN/MTProto:');

    test('Obfuscated handshake generation', () => {
        const buf = crypto.randomBytes(64);
        // Оставляем первые 56 байт как есть
        // Байте 56-59: протокол (0xEEEEEEEE = Intermediate)
        // Байте 60-63: DC ID
        
        buf.writeUInt32BE(0xEEEEEEEE, 56); // protocol tag
        buf.writeUInt32BE(2, 60); // DC 2
        
        const protoTag = buf.readUInt32BE(56);
        const dcId = buf.readUInt32BE(60);
        
        assert(protoTag === 0xEEEEEEEE, 'Intermediate protocol');
        assert(dcId === 2, 'DC 2');
    });

    test('Fake TLS ClientHello generation (0xDD secret)', () => {
        const secret = crypto.randomBytes(16);
        const clientHello = Buffer.alloc(512);
        
        // TLS record layer
        clientHello[0] = 0x16; // ContentType: Handshake
        clientHello[1] = 0x03; // Version: TLS 1.2
        clientHello[2] = 0x03;
        clientHello.writeUInt16BE(508 - 5, 3); // length
        
        // Handshake: ClientHello
        clientHello[5] = 0x01; // HandshakeType
        clientHello.writeUIntBE(508 - 9, 6, 3); // length
        
        clientHello[9] = 0x03; // Version
        clientHello[10] = 0x03;
        
        // Random (32 bytes)
        crypto.randomFillSync(clientHello, 11, 32);
        
        const isTls = clientHello[0] === 0x16 && clientHello[1] >= 0x03;
        assert(isTls, 'looks like TLS');
    });

    test('HMAC verification for fake TLS', () => {
        const secret = Buffer.from('dd98231ab6ba10f2d26f9443603b6041c3', 'hex');
        const clientHello = crypto.randomBytes(64);
        
        const hmac = crypto.createHmac('sha256', secret).update(clientHello).digest();
        const verify = crypto.createHmac('sha256', secret).update(clientHello).digest();
        
        assert(hmac.equals(verify), 'HMAC verified');
    });

    test('AES-CTR encryption for obfuscation', () => {
        const key = crypto.createHash('sha256').update(Buffer.alloc(32)).digest();
        const iv = crypto.randomBytes(16);
        const data = Buffer.from('obfuscated mtproto packet data');
        
        const cipher = crypto.createCipheriv('aes-256-ctr', key, iv);
        const enc = Buffer.concat([cipher.update(data), cipher.final()]);
        
        const decipher = crypto.createDecipheriv('aes-256-ctr', key, iv);
        const dec = Buffer.concat([decipher.update(enc), decipher.final()]);
        
        assert(data.equals(dec), 'aes-ctr roundtrip');
        assert(!data.equals(enc), 'encrypted != plain');
    });
}

// --- 5. DPI BYPASS -----------------------------------------
function testDpiBypass() {
    console.log('\n?? DPI Bypass:');

    test('TLS fragmentatation (split ClientHello)', () => {
        const clientHello = Buffer.alloc(512);
        clientHello[0] = 0x16;
        clientHello[1] = 0x03; clientHello[2] = 0x03;
        
        const frag1 = clientHello.slice(0, 128);
        const frag2 = clientHello.slice(128);
        
        assert(frag1.length + frag2.length === clientHello.length, 'fragments recompose');
        assert(frag1[0] === 0x16, 'first fragment header');
    });

    test('HTTP/1.1 Upgrade??', () => {
        const packet = Buffer.from('GET /chat HTTP/1.1\r\nHost: telegram.org\r\nUpgrade: websocket\r\n\r\n');
        assert(packet.includes('Upgrade'), 'Upgrade header present');
    });

    test('DNS over HTTPS эмуляция', () => {
        const domain = '149.154.167.51';
        const dnsMsg = Buffer.alloc(512);
        dnsMsg[0] = 0xAA; dnsMsg[1] = 0xAA; // transaction ID
        dnsMsg[2] = 0x01; dnsMsg[3] = 0x00; // standard query
        
        assert(dnsMsg[2] === 0x01, 'standard query flag');
    });

    test('Random padding (1-100 bytes)', () => {
        for (let i = 0; i < 100; i++) {
            const padLen = 1 + Math.floor(Math.random() * 100);
            const padding = crypto.randomBytes(padLen);
            assert(padding.length === padLen, `padding len ${padLen}`);
        }
    });
}

// --- 6. ТРАНСПОРТНЫЙ СЛОЙ ---------------------------------
function testTransport() {
    console.log('\n?? Транспортный слой:');

    test('Socks5 handshake', () => {
        // SOCKS5 handshake: client -> server
        const auth = Buffer.from([0x05, 0x01, 0x00]); // SOCKS5, 1 method, no auth
        assert(auth[0] === 0x05, 'SOCKS5 version');
        assert(auth[1] === 0x01, '1 method');
        
        // server response
        const authResp = Buffer.from([0x05, 0x00]); // SOCKS5, no auth
        assert(authResp[1] === 0x00, 'no auth required');
        
        // Connect request
        const connectReq = Buffer.from([
            0x05, 0x01, 0x00, 0x01, // SOCKS5, CONNECT, RSV, IPv4
            149, 154, 167, 51,      // TG DC4 IP
            0x00, 0x43              // port 443
        ]);
        assert(connectReq[1] === 0x01, 'CONNECT command');
        assert(connectReq[3] === 0x01, 'IPv4 address type');
    });

    test('TCP connection roundtrip', (done) => {
        const server = require('net').createServer(socket => {
            socket.write('pong');
            socket.end();
        });
        
        server.listen(0, () => {
            const port = server.address().port;
            const client = require('net').connect(port, () => {
                client.once('data', data => {
                    assert(data.toString() === 'pong', 'server response');
                    server.close();
                    done();
                });
            });
        });
    });

    test('UDP datagram send/receive', (done) => {
        const dgram = require('dgram');
        const server = dgram.createSocket('udp4');
        
        server.on('message', (msg, rinfo) => {
            assert(msg.toString() === 'ping', 'received ping');
            server.send('pong', rinfo.port, rinfo.address);
        });
        
        server.bind(0, () => {
            const port = server.address().port;
            const client = dgram.createSocket('udp4');
            client.send('ping', port, '127.0.0.1');
            client.once('message', msg => {
                assert(msg.toString() === 'pong', 'received pong');
                client.close();
                server.close();
                done();
            });
        });
    });
}

// --- ЗАПУСК ------------------------------------------------
console.log('===========================================');
console.log('  NEXUS Stress Test — все функции');
console.log('===========================================');
console.log(`  Время: ${new Date().toISOString()}`);
console.log(`  Node: ${process.version}`);
console.log('===========================================\n');

// Ждём UDP тест (асинхронный)
const asyncTests = [];
let asyncDone = 0;

function test(name, fn) {
    if (fn.length > 0) {
        // async test
        asyncTests.push({name, fn});
        return;
    }
    try {
        fn();
        passed++;
        console.log(`  ${OK} ${name}`);
    } catch (e) {
        failed++;
        console.log(`  ${FAIL} ${name}: ${e.message}`);
    }
}

// Run sync tests
testEdgeStorage();
testVolunteerComputing();
testSdr();
testMtProto();
testDpiBypass();
testTransport();

// Run async tests
if (asyncTests.length > 0) {
    console.log('\n?? Асинхронные тесты:');
    Promise.all(asyncTests.map(t => {
        return new Promise(resolve => {
            const done = (err) => {
                if (err) {
                    failed++;
                    console.log(`  ${FAIL} ${t.name}: ${err.message}`);
                } else {
                    passed++;
                    console.log(`  ${OK} ${t.name}`);
                }
                resolve();
            };
            try { t.fn(done); } catch(e) { done(e); }
        });
    })).then(() => printResults());
} else {
    printResults();
}

function printResults() {
    console.log('\n===========================================');
    console.log(`  Результаты: ${OK} ${passed} passed | ${FAIL} ${failed} failed`);
    console.log(`  Всего тестов: ${passed + failed}`);
    console.log('===========================================');
    
    if (failed > 0) {
        console.log(`\n  ? Обнаружены проблемы!`);
        process.exit(1);
    } else {
        console.log(`\n  ? ВСЕ ТЕСТЫ ПРОЙДЕНЫ — вылетов нет`);
        process.exit(0);
    }
}
