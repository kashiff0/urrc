'use strict';

// Roku External Control Protocol (ECP) client.
// ECP is unauthenticated HTTP on port 8060, LAN-only. Key presses are POSTs,
// queries are GETs returning XML.

const http = require('node:http');
const dgram = require('node:dgram');

const ECP_PORT = 8060;
const SSDP_ADDR = '239.255.255.250';
const SSDP_PORT = 1900;

// Keys the Roku accepts on /keypress. Volume and power are forwarded to the TV
// over HDMI-CEC by stick/streambar models — they are no-ops on set-top boxes.
const KEYS = new Set([
  'home', 'rev', 'fwd', 'play', 'select', 'left', 'right', 'down', 'up', 'back',
  'instantreplay', 'info', 'backspace', 'search', 'enter', 'find_remote',
  'volumedown', 'volumemute', 'volumeup', 'poweroff', 'poweron', 'power',
  'channelup', 'channeldown', 'inputtuner', 'inputhdmi1', 'inputhdmi2',
  'inputhdmi3', 'inputhdmi4', 'inputav1',
]);

function request(host, method, path, { timeout = 5000, raw = false } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host, port: ECP_PORT, method, path, timeout },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const body = Buffer.concat(chunks);
          if (res.statusCode >= 400) {
            reject(new Error(`Roku returned ${res.statusCode} for ${path}`));
            return;
          }
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: raw ? body : body.toString('utf8'),
          });
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error(`Timed out talking to ${host}`)));
    req.on('error', reject);
    req.end();
  });
}

const keypress = (host, key) => request(host, 'POST', `/keypress/${key}`);
const keydown = (host, key) => request(host, 'POST', `/keydown/${key}`);
const keyup = (host, key) => request(host, 'POST', `/keyup/${key}`);
const launch = (host, appId) => request(host, 'POST', `/launch/${encodeURIComponent(appId)}`);

// Text entry into on-screen keyboards. Each character is its own keypress, so
// we send them sequentially — the Roku drops them if they arrive in parallel.
async function typeText(host, text) {
  for (const char of [...text]) {
    await keypress(host, `Lit_${encodeURIComponent(char)}`);
  }
}

const icon = (host, appId) =>
  request(host, 'GET', `/query/icon/${encodeURIComponent(appId)}`, { raw: true });

// The XML here is flat and machine-generated, so targeted regex beats pulling in
// a parser dependency. Anything unrecognized simply comes back empty.
function attr(tag, name) {
  const m = tag.match(new RegExp(`${name}="([^"]*)"`));
  return m ? decodeEntities(m[1]) : '';
}

function decodeEntities(s) {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

async function queryApps(host) {
  const { body } = await request(host, 'GET', '/query/apps');
  const apps = [];
  const re = /<app([^>]*)>([^<]*)<\/app>/g;
  let m;
  while ((m = re.exec(body)) !== null) {
    apps.push({
      id: attr(m[1], 'id'),
      type: attr(m[1], 'type'),
      version: attr(m[1], 'version'),
      name: decodeEntities(m[2]).trim(),
    });
  }
  return apps;
}

async function queryActiveApp(host) {
  const { body } = await request(host, 'GET', '/query/active-app');
  const m = body.match(/<app([^>]*)>([^<]*)<\/app>/);
  if (!m) return null;
  const id = attr(m[1], 'id');
  const name = decodeEntities(m[2]).trim();
  // The home screen reports itself with no id.
  return { id: id || null, name: name || 'Home' };
}

async function queryDeviceInfo(host) {
  const { body } = await request(host, 'GET', '/query/device-info');
  const info = {};
  const re = /<([a-zA-Z0-9-]+)>([^<]*)<\/\1>/g;
  let m;
  while ((m = re.exec(body)) !== null) info[m[1]] = decodeEntities(m[2]).trim();
  return {
    name: info['user-device-name'] || info['friendly-device-name'] || info['model-name'] || 'Roku',
    model: info['model-name'] || '',
    serial: info['serial-number'] || '',
    powerMode: info['power-mode'] || '',
    // Only sticks/soundbars wired into an HDMI port relay volume + power to the TV.
    supportsTvControl:
      info['supports-ecs-microphone'] !== undefined ||
      /stick|streambar|express|premiere|ultra/i.test(info['model-name'] || ''),
    raw: info,
  };
}

// SSDP M-SEARCH scoped to Roku's ECP service type. Rokus answer within ~1s;
// we listen a little longer to catch slow or sleeping devices.
function discover({ timeout = 2500 } = {}) {
  return new Promise((resolve) => {
    const found = new Map();
    const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });
    const message = Buffer.from(
      'M-SEARCH * HTTP/1.1\r\n' +
        `HOST: ${SSDP_ADDR}:${SSDP_PORT}\r\n` +
        'MAN: "ssdp:discover"\r\n' +
        'ST: roku:ecp\r\n' +
        'MX: 2\r\n\r\n',
    );

    const finish = () => {
      try {
        socket.close();
      } catch {
        /* already closed */
      }
      resolve([...found.values()]);
    };

    socket.on('error', finish);
    socket.on('message', (msg, rinfo) => {
      const text = msg.toString('utf8');
      if (!/roku:ecp/i.test(text)) return;
      const location = text.match(/LOCATION:\s*http:\/\/([\d.]+):(\d+)/i);
      const host = location ? location[1] : rinfo.address;
      const usn = text.match(/USN:\s*(.+)/i);
      found.set(host, { host, usn: usn ? usn[1].trim() : '' });
    });

    socket.bind(() => {
      socket.setBroadcast(true);
      socket.send(message, SSDP_PORT, SSDP_ADDR);
      // Retry once — the first datagram is often lost while the multicast
      // group membership is still settling.
      setTimeout(() => socket.send(message, SSDP_PORT, SSDP_ADDR), 600);
      setTimeout(finish, timeout);
    });
  });
}

// Discovery gives us IPs; names require a follow-up query per device.
async function discoverWithNames(opts) {
  const devices = await discover(opts);
  return Promise.all(
    devices.map(async (device) => {
      try {
        const info = await queryDeviceInfo(device.host);
        return { ...device, name: info.name, model: info.model };
      } catch {
        return { ...device, name: device.host, model: '' };
      }
    }),
  );
}

module.exports = {
  KEYS,
  ECP_PORT,
  keypress,
  keydown,
  keyup,
  launch,
  typeText,
  icon,
  queryApps,
  queryActiveApp,
  queryDeviceInfo,
  discover,
  discoverWithNames,
};
