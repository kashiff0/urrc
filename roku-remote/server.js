#!/usr/bin/env node
'use strict';

// Serves the remote UI to your phone and proxies its taps to the Roku.
//
// The proxy is not optional plumbing: Roku's ECP sends no CORS headers, and iOS
// Safari blocks an HTTPS page from calling a plain-HTTP LAN address at all. So
// the phone talks to this server over HTTP on your LAN, and this server talks
// to the Roku.

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');

const ecp = require('./lib/ecp');
const sony = require('./lib/sony');

const PORT = Number(process.env.PORT) || 8080;
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'public');
const CONFIG_PATH = process.env.REMOTE_CONFIG || path.join(__dirname, 'config.json');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

let config = { rokuHost: process.env.ROKU_HOST || null, sony: null };

async function loadConfig() {
  try {
    const parsed = JSON.parse(await fsp.readFile(CONFIG_PATH, 'utf8'));
    config = { ...config, ...parsed };
    if (process.env.ROKU_HOST) config.rokuHost = process.env.ROKU_HOST;
  } catch (err) {
    if (err.code !== 'ENOENT') console.warn(`Ignoring unreadable config: ${err.message}`);
  }
}

async function saveConfig() {
  await fsp.writeFile(CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`);
}

// If no Roku was configured, find one and remember it. Keeps first run to a
// single tap instead of making people hunt for an IP address.
let autoDiscovery = null;
async function resolveRoku() {
  if (config.rokuHost) return config.rokuHost;
  if (!autoDiscovery) {
    autoDiscovery = (async () => {
      const devices = await ecp.discoverWithNames();
      if (devices.length) {
        config.rokuHost = devices[0].host;
        await saveConfig().catch(() => {});
      }
      autoDiscovery = null;
      return config.rokuHost;
    })();
  }
  return autoDiscovery;
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Cache-Control': 'no-store', ...headers });
  res.end(body);
}

const sendJson = (res, status, data) =>
  send(res, status, JSON.stringify(data), { 'Content-Type': 'application/json; charset=utf-8' });

function readBody(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error('Request body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      const text = Buffer.concat(chunks).toString('utf8');
      if (!text) return resolve({});
      try {
        resolve(JSON.parse(text));
      } catch {
        reject(new Error('Request body was not valid JSON'));
      }
    });
    req.on('error', reject);
  });
}

async function serveStatic(req, res, pathname) {
  const relative = pathname === '/' ? 'index.html' : decodeURIComponent(pathname).replace(/^\/+/, '');
  const filePath = path.join(PUBLIC_DIR, relative);
  // Never let a crafted path escape the public directory.
  if (!filePath.startsWith(PUBLIC_DIR + path.sep) && filePath !== path.join(PUBLIC_DIR, 'index.html')) {
    send(res, 403, 'Forbidden');
    return;
  }
  try {
    const data = await fsp.readFile(filePath);
    const type = MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    // Icons are content-addressed by name and never change; everything else is
    // small enough that revalidating each load beats debugging a stale cache.
    const cache = filePath.includes(`${path.sep}icons${path.sep}`)
      ? 'public, max-age=604800'
      : 'no-cache';
    send(res, 200, data, { 'Content-Type': type, 'Cache-Control': cache });
  } catch {
    send(res, 404, 'Not found');
  }
}

const iconCache = new Map();

async function handleApi(req, res, url) {
  const parts = url.pathname.split('/').filter(Boolean).slice(1); // drop "api"
  const [section, ...rest] = parts;
  const method = req.method;

  if (section === 'config') {
    if (method === 'GET') {
      return sendJson(res, 200, {
        rokuHost: config.rokuHost,
        // Never echo the pre-shared key back to the browser.
        sony: config.sony ? { host: config.sony.host, mac: config.sony.mac || null, configured: true } : null,
      });
    }
    if (method === 'POST' || method === 'PUT') {
      const body = await readBody(req);
      if ('rokuHost' in body) config.rokuHost = body.rokuHost || null;
      if ('sony' in body) {
        config.sony = body.sony && body.sony.host
          ? {
              host: body.sony.host,
              // An empty psk in an update means "keep the existing one".
              psk: body.sony.psk || (config.sony && config.sony.psk) || '',
              mac: body.sony.mac || (config.sony && config.sony.mac) || null,
            }
          : null;
      }
      await saveConfig();
      return sendJson(res, 200, { ok: true, rokuHost: config.rokuHost });
    }
  }

  if (section === 'discover' && method === 'GET') {
    const devices = await ecp.discoverWithNames();
    return sendJson(res, 200, { devices, selected: config.rokuHost });
  }

  // Everything past this point needs a Roku.
  const host = await resolveRoku();
  if (!host) {
    return sendJson(res, 503, {
      error: 'No Roku found. Make sure the phone and this server are on the same Wi-Fi, or enter the IP manually.',
    });
  }

  if (section === 'status' && method === 'GET') {
    const [info, active] = await Promise.all([
      ecp.queryDeviceInfo(host),
      ecp.queryActiveApp(host).catch(() => null),
    ]);
    return sendJson(res, 200, {
      host,
      name: info.name,
      model: info.model,
      powerMode: info.powerMode,
      supportsTvControl: info.supportsTvControl,
      activeApp: active,
      tvControl: config.sony ? 'ip' : 'cec',
    });
  }

  if ((section === 'key' || section === 'keydown' || section === 'keyup') && method === 'POST') {
    const key = rest.join('/');
    // Literal characters are validated by the typing endpoint instead.
    if (!ecp.KEYS.has(key)) return sendJson(res, 400, { error: `Unknown key "${key}"` });
    const fn = section === 'key' ? ecp.keypress : section === 'keydown' ? ecp.keydown : ecp.keyup;
    await fn(host, key);
    return sendJson(res, 200, { ok: true, key });
  }

  if (section === 'type' && method === 'POST') {
    const { text } = await readBody(req);
    if (typeof text !== 'string' || !text.length) {
      return sendJson(res, 400, { error: 'Expected a non-empty "text" string' });
    }
    await ecp.typeText(host, text.slice(0, 200));
    return sendJson(res, 200, { ok: true });
  }

  if (section === 'apps' && method === 'GET') {
    return sendJson(res, 200, { apps: await ecp.queryApps(host) });
  }

  if (section === 'icon' && method === 'GET') {
    const appId = rest.join('/');
    const cacheKey = `${host}:${appId}`;
    let cached = iconCache.get(cacheKey);
    if (!cached) {
      const { body, headers } = await ecp.icon(host, appId);
      cached = { body, type: headers['content-type'] || 'image/png' };
      iconCache.set(cacheKey, cached);
    }
    return send(res, 200, cached.body, {
      'Content-Type': cached.type,
      'Cache-Control': 'public, max-age=86400',
    });
  }

  if (section === 'launch' && method === 'POST') {
    const appId = rest.join('/');
    await ecp.launch(host, appId);
    return sendJson(res, 200, { ok: true, appId });
  }

  // Direct Sony control, used only when the TV has been configured. Otherwise
  // these same actions ride HDMI-CEC through the /api/key endpoints.
  if (section === 'tv') {
    if (!config.sony) return sendJson(res, 400, { error: 'No Sony TV configured' });
    const action = rest[0];
    const body = method === 'POST' ? await readBody(req) : {};
    switch (action) {
      case 'power':
        if (body.on && config.sony.mac) await sony.wake(config.sony.mac).catch(() => {});
        return sendJson(res, 200, { ok: true, result: await sony.setPower(config.sony, body.on) });
      case 'volume':
        return sendJson(res, 200, { ok: true, result: await sony.setVolume(config.sony, body.value) });
      case 'mute':
        return sendJson(res, 200, { ok: true, result: await sony.setMute(config.sony, body.on) });
      case 'input':
        return sendJson(res, 200, { ok: true, result: await sony.setInput(config.sony, body.port) });
      case 'status': {
        const [power, volume] = await Promise.all([
          sony.getPower(config.sony).catch(() => null),
          sony.getVolume(config.sony).catch(() => null),
        ]);
        return sendJson(res, 200, { power, volume });
      }
      default:
        return sendJson(res, 404, { error: `Unknown TV action "${action}"` });
    }
  }

  return sendJson(res, 404, { error: 'Unknown endpoint' });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    return send(res, 204, '', {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
  }

  if (url.pathname.startsWith('/api/')) {
    try {
      await handleApi(req, res, url);
    } catch (err) {
      if (!res.headersSent) sendJson(res, 502, { error: err.message });
    }
    return;
  }

  if (req.method === 'GET' || req.method === 'HEAD') return serveStatic(req, res, url.pathname);
  send(res, 405, 'Method not allowed');
});

function lanAddresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((iface) => iface && iface.family === 'IPv4' && !iface.internal)
    .map((iface) => iface.address);
}

async function main() {
  await loadConfig();
  server.listen(PORT, HOST, () => {
    const addresses = lanAddresses();
    console.log('\n  Roku remote is running.\n');
    if (addresses.length) {
      console.log('  Open this on your iPhone (same Wi-Fi), then Share -> Add to Home Screen:\n');
      for (const address of addresses) console.log(`    http://${address}:${PORT}`);
    } else {
      console.log(`  http://localhost:${PORT}  (no LAN address detected)`);
    }
    console.log(
      config.rokuHost
        ? `\n  Roku: ${config.rokuHost}\n`
        : '\n  No Roku configured yet — the app will scan for one on first load.\n',
    );
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { server, main };
