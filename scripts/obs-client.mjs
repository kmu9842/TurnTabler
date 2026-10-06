// Local verification only. Credentials remain in OBS's own configuration file.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';

export async function connectOBS() {
  const config = JSON.parse(readFileSync(join(process.env.APPDATA, 'obs-studio/plugin_config/obs-websocket/config.json'), 'utf8'));
  const socket = new WebSocket(`ws://127.0.0.1:${config.server_port}`);
  const pending = new Map(), listeners = new Set();
  let sequence = 0;
  const hash = text => createHash('sha256').update(text).digest('base64');
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('OBS connection timeout')), 12000);
    socket.onerror = () => { clearTimeout(timeout); reject(new Error('OBS local connection failed')); };
    socket.onmessage = event => {
      const {op,d} = JSON.parse(event.data);
      if (op === 0) {
        const identification = {rpcVersion:1,eventSubscriptions:1 | (1 << 16)};
        if (d.authentication) identification.authentication = hash(hash(config.server_password + d.authentication.salt) + d.authentication.challenge);
        socket.send(JSON.stringify({op:1,d:identification}));
      } else if (op === 2) { clearTimeout(timeout); resolve(); }
      else if (op === 7) {
        const request = pending.get(d.requestId);
        if (request) { pending.delete(d.requestId); clearTimeout(request.timer); d.requestStatus.result ? request.resolve(d.responseData || {}) : request.reject(new Error(`${d.requestType}: ${d.requestStatus.comment}`)); }
      } else if (op === 5) { for (const listener of listeners) listener(d); }
    };
  });
  return {
    request(requestType, requestData = {}) {
      const requestId = String(++sequence);
      return new Promise((resolve,reject) => {
        const timer = setTimeout(() => { pending.delete(requestId); reject(new Error(`${requestType} timeout`)); },12000);
        pending.set(requestId,{resolve,reject,timer});
        socket.send(JSON.stringify({op:6,d:{requestType,requestId,requestData}}));
      });
    },
    onEvent(listener) { listeners.add(listener); return () => listeners.delete(listener); },
    close() { socket.close(); }
  };
}
