'use strict';

// Optional direct control of a Sony Bravia over its local REST API.
//
// HDMI-CEC through the Roku handles volume and power for most people, but CEC
// power-on is unreliable once the TV has been off for a while. When the TV's IP
// and pre-shared key are configured we can drive it directly instead.
//
// Enable on the TV: Settings -> Network -> Home Network Setup ->
// IP Control -> Authentication: "Normal and Pre-Shared Key", then set the key.

const http = require('node:http');
const dgram = require('node:dgram');

function rpc(config, service, method, params = [{}], version = '1.0') {
  const payload = JSON.stringify({ method, id: 1, params, version });
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: config.host,
        port: config.port || 80,
        method: 'POST',
        path: `/sony/${service}`,
        timeout: 5000,
        headers: {
          'Content-Type': 'application/json',
          'X-Auth-PSK': config.psk || '',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let parsed;
          try {
            parsed = JSON.parse(text);
          } catch {
            reject(new Error(`Bravia returned non-JSON (HTTP ${res.statusCode})`));
            return;
          }
          if (parsed.error) {
            // Bravia errors are [code, message]; 403 means a bad pre-shared key.
            const [code, message] = parsed.error;
            reject(new Error(`Bravia error ${code}: ${message || 'unknown'}`));
            return;
          }
          resolve(parsed.result ? parsed.result[0] : null);
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error('Timed out talking to the TV')));
    req.on('error', reject);
    req.end(payload);
  });
}

const setPower = (config, on) =>
  rpc(config, 'system', 'setPowerStatus', [{ status: !!on }]);

const getPower = (config) => rpc(config, 'system', 'getPowerStatus');

// Volume takes a signed relative step ("+1") or an absolute level ("18").
const setVolume = (config, value) =>
  rpc(config, 'audio', 'setAudioVolume', [{ target: 'speaker', volume: String(value) }]);

const setMute = (config, on) => rpc(config, 'audio', 'setAudioMute', [{ status: !!on }]);

const getVolume = (config) => rpc(config, 'audio', 'getVolumeInformation');

const setInput = (config, port) =>
  rpc(config, 'avContent', 'setPlayContent', [{ uri: `extInput:hdmi?port=${port}` }]);

const getInputs = (config) =>
  rpc(config, 'avContent', 'getCurrentExternalInputsStatus', [], '1.1');

// A Bravia in deep standby drops off the network entirely, so the REST call
// can't reach it. Wake-on-LAN is the only way back — requires the TV's
// "Remote start" / "Wake on LAN" setting and its MAC address.
function wake(mac) {
  return new Promise((resolve, reject) => {
    const clean = mac.replace(/[^a-fA-F0-9]/g, '');
    if (clean.length !== 12) {
      reject(new Error(`"${mac}" is not a MAC address`));
      return;
    }
    const bytes = Buffer.from(clean, 'hex');
    const packet = Buffer.concat([Buffer.alloc(6, 0xff), Buffer.alloc(6 * 16)]);
    for (let i = 0; i < 16; i++) bytes.copy(packet, 6 + i * 6);

    const socket = dgram.createSocket('udp4');
    socket.on('error', (err) => {
      socket.close();
      reject(err);
    });
    socket.bind(() => {
      socket.setBroadcast(true);
      socket.send(packet, 9, '255.255.255.255', (err) => {
        socket.close();
        if (err) reject(err);
        else resolve({ sent: true });
      });
    });
  });
}

module.exports = {
  setPower,
  getPower,
  setVolume,
  setMute,
  getVolume,
  setInput,
  getInputs,
  wake,
};
