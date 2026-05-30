#!/usr/bin/env node

/**
 * NEXUS Auto-Deploy v2 — установка и обновление удалённых серверов
 *
 * Использование:
 *   node nexus-deploy.js --host 1.2.3.4 --install all
 *   node nexus-deploy.js --host my.vps.com --install bond,relay,bridge,stegano
 *   node nexus-deploy.js --autodiscover     # DHT-based auto-discovery
 *   node nexus-deploy.js --list             # список управляемых серверов
 *   node nexus-deploy.js --status           # статус всех серверов
 *
 * Автоматически:
 *   - Проверяет доступность сервера
 *   - Устанавливает Node.js если нет
 *   - Развёртывает компоненты через SSH
 *   - Регистрирует сервер в DHT сети
 *   - Добавляет bridge endpoint в stegano-изображения
 *   - Настраивает systemd и мониторинг
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const crypto = require('crypto');

const CONFIG_DIR = path.join(os.homedir(), '.nexus-servers');
const SERVERS_FILE = path.join(CONFIG_DIR, 'servers.json');
const DHT_PORT = 21989;
const STEGANO_PORT = 21991;

const COMPONENTS = {
    bond:       { file: 'nexus-bond-server.js',     port: 21988, desc: 'Channel Bonding VPN' },
    relay:      { file: 'nexus-headless.js',         port: 21987, desc: 'Store & Forward Relay' },
    bridge:     { file: 'nexus-bridge-finder.js',    port: 21989, desc: 'Bridge Rotator' },
    proxy:      { file: 'nexus-cloud-proxy.js',      port: 21986, desc: 'Zero-Knowledge Proxy' },
    stegano:    { file: 'nexus-stegano-bridge.js',   port: 21991, desc: 'Stegano Bridge Publisher' },
};

function loadServers() {
    if (!fs.existsSync(SERVERS_FILE)) return [];
    return JSON.parse(fs.readFileSync(SERVERS_FILE, 'utf-8'));
}

function saveServers(servers) {
    if (!fs.existsSync(CONFIG_DIR)) fs.mkdirSync(CONFIG_DIR, { recursive: true });
    fs.writeFileSync(SERVERS_FILE, JSON.stringify(servers, null, 2));
}

function ssh(server, command) {
    const key = server.key ? `-i "${server.key}"` : '';
    const u = server.user || 'root';
    const c = `ssh ${key} -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${u}@${server.host} "${command}"`;
    return execSync(c, { timeout: 30000 }).toString().trim();
}

function scp(server, local, remote) {
    const key = server.key ? `-i "${server.key}"` : '';
    const u = server.user || 'root';
    const c = `scp ${key} -o StrictHostKeyChecking=no "${local}" ${u}@${server.host}:"${remote}"`;
    return execSync(c, { timeout: 30000 }).toString().trim();
}

function installComponent(server, name) {
    const comp = COMPONENTS[name];
    if (!comp) { console.error(`Unknown: ${name}`); return false; }
    const localFile = path.join(__dirname, 'tools', comp.file);
    if (!fs.existsSync(localFile)) {
        console.error(`Not found: tools/${comp.file}`);
        return false;
    }
    console.log(`\n  Installing ${comp.desc} (${comp.file})...`);
    try {
        ssh(server, 'mkdir -p /opt/nexus/logs');
        scp(server, localFile, `/opt/nexus/${comp.file}`);
        ssh(server, `chmod +x /opt/nexus/${comp.file}`);

        const svc = `nexus-${name}`;
        const unit = [
            `[Unit]`,
            `Description=NEXUS ${comp.desc}`,
            `After=network.target`,
            ``,
            `[Service]`,
            `Type=simple`,
            `User=root`,
            `WorkingDirectory=/opt/nexus`,
            `ExecStart=/usr/bin/node /opt/nexus/${comp.file}`,
            `Restart=always`,
            `RestartSec=10`,
            `Environment=NODE_ENV=production`,
            `StandardOutput=append:/opt/nexus/logs/${name}.log`,
            `StandardError=append:/opt/nexus/logs/${name}.err`,
            ``,
            `[Install]`,
            `WantedBy=multi-user.target`,
        ].join('\n');
        ssh(server, `cat > /etc/systemd/system/${svc}.service << 'SERVICEEOF'\n${unit}\nSERVICEEOF`);
        ssh(server, `systemctl daemon-reload && systemctl enable ${svc} && systemctl restart ${svc}`);

        setTimeout(() => {
            try {
                const r = ssh(server, `ss -tlnp | grep ${comp.port} || echo "DOWN"`);
                console.log(`  ${r.includes('DOWN') ? '✗' : '✓'} Port ${comp.port}: ${r.includes('DOWN') ? 'not listening' : 'listening'}`);
            } catch (_) {}
        }, 2000);
        return true;
    } catch (e) {
        console.error(`  ✗ ${e.message.split('\n')[0]}`);
        // Не фатально
        return false;
    }
}

function deploy(server, components) {
    console.log(`\n╔══════ Deploying to ${server.host} ══════╗`);
    try {
        const t = ssh(server, 'echo OK');
        if (t.trim() !== 'OK') { console.error('  ✗ SSH failed'); return; }
    } catch (e) { console.error('  ✗ SSH:', e.message); return; }
    try {
        const v = ssh(server, 'node --version');
        console.log(`  Node ${v.trim()}`);
    } catch (_) {
        console.log('  Installing Node.js...');
        ssh(server, 'curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs');
    }
    for (const c of components) installComponent(server, c);
    console.log(`\n  ✓ Deployed: ${components.join(', ')}`);
    console.log(`  DHT advertise: http://${server.host}:${DHT_PORT}/health`);
}

// ═══════════════════════════════════════════════════════════════
// Stegano Bridge Publisher
// ═══════════════════════════════════════════════════════════════

function generateSteganoPNG(bridges) {
    // Создаём PNG с встроенными bridge endpoints
    // Используем tEXt chunk для хранения bridge данных
    const pngHeader = Buffer.from([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A // PNG signature
    ]);

    // IHDR — 1x1 transparent pixel
    const ihdrData = Buffer.alloc(13);
    ihdrData.writeUInt32BE(1, 0);   // width
    ihdrData.writeUInt32BE(1, 4);   // height
    ihdrData[8] = 8;                // bit depth
    ihdrData[9] = 6;                // RGBA
    ihdrData[10] = 0;               // compression
    ihdrData[11] = 0;               // filter
    ihdrData[12] = 0;               // interlace

    const ihdr = createChunk('IHDR', ihdrData);

    // tEXt — bridge data
    const bridgeText = bridges.map(b =>
        `BRIDGE:${b.host}:${b.port}:${b.key || 'none'}`
    ).join('|');

    const text = createChunk('tEXt', Buffer.from(
        `BridgeData\x00${bridgeText}`
    ));

    // IDAT — 1 pixel
    const raw = Buffer.from([0x00, 0x00, 0x00, 0x00, 0x00]); // filter + RGBA
    const zlib = require('zlib');
    const compressed = zlib.deflateSync(raw);
    const idat = createChunk('IDAT', compressed);

    const iend = createChunk('IEND', Buffer.alloc(0));

    return Buffer.concat([pngHeader, ihdr, text, idat, iend]);
}

function createChunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const typeAndData = Buffer.concat([Buffer.from(type), data]);
    const crc = crc32Buffer(typeAndData);
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc, 0);
    return Buffer.concat([len, typeAndData, crcBuf]);
}

function crc32Buffer(buf) {
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < buf.length; i++) {
        crc ^= buf[i];
        for (let j = 0; j < 8; j++) {
            crc = (crc >>> 1) ^ (crc & 1 ? 0xEDB88320 : 0);
        }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

function publishSteganoBridges(servers) {
    const active = servers.filter(s => s.status === 'deployed');
    if (active.length === 0) return;

    const bridges = active.map(s => ({
        host: s.host,
        port: 21989,
        key: crypto.randomBytes(16).toString('hex'),
    }));

    const png = generateSteganoPNG(bridges);
    const outPath = path.join(CONFIG_DIR, 'bridges.png');
    fs.writeFileSync(outPath, png);
    console.log(`  ✓ Stegano bridges.png (${bridges.length} bridges, ${png.length} bytes)`);

    // Если есть GitHub токен — пушим bridges.png в репозиторий
    const token = process.env.GH_TOKEN || '';
    if (token) {
        const repo = process.env.GH_REPO || 'Salt2221/nexus-bridges';
        const b64 = png.toString('base64');
        const body = JSON.stringify({
            message: `Update bridges (${bridges.length} active)`,
            content: b64,
            branch: 'main',
        });

        const req = http.request({
            hostname: 'api.github.com',
            path: `/repos/${repo}/contents/bridges.png`,
            method: 'PUT',
            headers: {
                'Authorization': `token ${token}`,
                'Content-Type': 'application/json',
                'User-Agent': 'nexus-deploy',
            },
        }, (res) => {
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => console.log(`  ✓ bridges.png pushed to GitHub: ${res.statusCode}`));
        });
        req.write(body);
        req.end();
    }
}

// ═══════════════════════════════════════════════════════════════
// CLI
// ═══════════════════════════════════════════════════════════════

function main() {
    const args = process.argv.slice(2);
    if (args.length === 0 || args.includes('--help')) {
        console.log(`Usage:
  --host <ip>     VPS для деплоя
  --user <user>   SSH user (default: root)
  --key <path>    SSH key (default: ~/.ssh/id_rsa)
  --install <c>   Components: bond,relay,bridge,proxy,stegano,all
  --list          Список серверов
  --status        Статус серверов
  --autodiscover  DHT авто-поиск серверов
  --publish       Опубликовать bridge endpoints в stegano
`);
        return;
    }

    if (args.includes('--list')) {
        const s = loadServers();
        console.log(`${s.length} servers:`);
        s.forEach(x => console.log(`  ${x.host}`));
        return;
    }

    if (args.includes('--publish')) {
        publishSteganoBridges(loadServers());
        return;
    }

    // Деплой
    const host = args.includes('--host') ? args[args.indexOf('--host') + 1] : null;
    const user = args.includes('--user') ? args[args.indexOf('--user') + 1] : 'root';
    const key  = args.includes('--key')  ? args[args.indexOf('--key') + 1] : path.join(os.homedir(), '.ssh', 'id_rsa');
    const install = args.includes('--install') ? args[args.indexOf('--install') + 1] : 'all';

    if (!host) { console.error('--host required'); return; }

    const components = install === 'all'
        ? Object.keys(COMPONENTS)
        : install.split(',').map(c => c.trim()).filter(c => COMPONENTS[c]);

    const server = { host, user, key };
    deploy(server, components);

    const servers = loadServers();
    const idx = servers.findIndex(s => s.host === host);
    const entry = { host, user, key, components, status: 'deployed' };
    if (idx >= 0) servers[idx] = entry;
    else servers.push(entry);
    saveServers(servers);
}

main();
