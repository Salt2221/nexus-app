#!/usr/bin/env node
// Create GitHub release + upload APK
const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const OWNER = 'Salt2221';
const REPO = 'nexus-app';
const APK_PATH = 'C:\\Users\\roman\\.openclaw\\workspace\\nexus\\build\\app\\outputs\\flutter-apk\\app-debug.apk';
const TAG = 'v1.0.3';
const NAME = 'NEXUS v1.0.3';
const BODY = `## NEXUS v1.0.3

### Что нового
- **VpnService** — запрос разрешения через system dialog (VpnService.prepare)
- **MethodChannel** — startVpn / stopVpn через нативный код
- **Статус VPN** — отображается на экране
- **DPI стратегии** — 11 стратегий адаптировано из Zapret
- **Новая иконка** — гексагон
- **Автообновление конфигурации** — через GitHub

### Сборка
- Flutter 3.32.0
- Android SDK 34
- arm64-v8a
- Debug`;

const TOKEN = process.env.GH_TOKEN || (() => {
  const remote = execSync('git remote get-url origin').toString().trim();
  const match = remote.match(/https:\/\/[^:]+:(.+)@/);
  return match ? match[1] : null;
})();

if (!TOKEN) {
  console.error('GH_TOKEN not set and unable to extract from git remote');
  process.exit(1);
}

function apiRequest(method, endpoint, body = null) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'api.github.com',
      path: `/repos/${OWNER}/${REPO}/${endpoint}`,
      method,
      headers: {
        'Authorization': `Bearer ${TOKEN}`,
        'User-Agent': 'nexus-release-creator',
        'Accept': 'application/vnd.github+json',
      },
    };
    if (body) opts.headers['Content-Type'] = 'application/json';
    
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function uploadAsset(uploadUrl, filePath, name) {
  const stat = fs.statSync(filePath);
  const content = fs.readFileSync(filePath);
  
  return new Promise((resolve, reject) => {
    let url = uploadUrl.replace('{?name,label}', `?name=${name}`);
    const opts = new URL(url);
    const req = https.request({
      hostname: opts.hostname,
      path: opts.pathname + opts.search,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TOKEN}`,
        'User-Agent': 'nexus-release-creator',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/vnd.android.package-archive',
        'Content-Length': stat.size,
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    req.on('error', reject);
    req.write(content);
    req.end();
  });
}

(async () => {
  console.log('Checking existing release...');
  const existing = await apiRequest('GET', `releases/tags/${TAG}`);
  if (existing.status === 200 && existing.data.id) {
    console.log('Deleting existing release...');
    await apiRequest('DELETE', `releases/${existing.data.id}`);
  }
  
  try {
    const ref = await apiRequest('GET', `git/ref/tags/${TAG}`);
    if (ref.status === 200) {
      console.log('Deleting existing tag...');
      await apiRequest('DELETE', `git/refs/tags/${TAG}`);
    }
  } catch {}
  
  console.log('Creating release...');
  const release = await apiRequest('POST', 'releases', {
    tag_name: TAG,
    name: NAME,
    body: BODY,
    draft: false,
    prerelease: false,
  });
  
  if (release.status !== 201) {
    console.error('Failed to create release:', JSON.stringify(release.data, null, 2));
    process.exit(1);
  }
  
  console.log('Release created:', release.data.html_url);
  
  console.log('Uploading APK...');
  const apkName = `NEXUS-v${TAG.slice(1)}-debug.apk`;
  const upload = await uploadAsset(release.data.upload_url, APK_PATH, apkName);
  
  if (upload.status === 201) {
    console.log('APK uploaded:', upload.data.browser_download_url);
  } else {
    console.error('Upload failed:', JSON.stringify(upload.data, null, 2));
  }
})();
