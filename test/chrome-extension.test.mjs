import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { normalizeYouTube, clickedYouTube } from '../chrome-extension/extension/youtube.mjs';

const watch = 'https://www.youtube.com/watch?v=2qfoSxRRCJc';
test('video variants, playlist/mix/index/timestamp survive normalization', () => {
  for (const url of [watch, 'https://youtu.be/2qfoSxRRCJc', 'https://m.youtube.com/shorts/2qfoSxRRCJc',
    'https://youtube.com/live/2qfoSxRRCJc', 'https://youtube.com/embed/2qfoSxRRCJc', 'https://music.youtube.com/watch?v=2qfoSxRRCJc']) {
    assert.equal(normalizeYouTube(url), watch);
  }
  assert.equal(normalizeYouTube(`${watch}&list=RD2qfoSxRRCJc&index=2&t=1m23s&si=tracking`), `${watch}&list=RD2qfoSxRRCJc&index=2&t=1m23s`);
  assert.equal(normalizeYouTube('https://youtube.com/playlist?list=PL1234567890'), 'https://www.youtube.com/playlist?list=PL1234567890');
  assert.equal(normalizeYouTube(`${watch}&start=60`), `${watch}&t=60`);
  assert.equal(normalizeYouTube(`${watch}&index=-1&t=bad`), watch);
});

test('reject invalid hosts, credentials, IDs, protocols and non-video pages', () => {
  for (const url of ['https://youtube.com.evil.org/watch?v=2qfoSxRRCJc', 'file:///C:/test', 'javascript:alert(1)',
    'https://user@youtube.com/watch?v=2qfoSxRRCJc', 'https://youtube.com/watch?v=bad', 'https://youtube.com/playlist?list=bad',
    'https://youtube.com/', 'https://youtube.com/@channel', undefined]) assert.throws(() => normalizeYouTube(url));
});

test('clicked thumbnail wins over current video; invalid clicked link never falls back', () => {
  const next = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  assert.equal(clickedYouTube({ linkUrl: next, pageUrl: watch }), next);
  assert.equal(clickedYouTube({ frameUrl: 'https://www.youtube.com/embed/2qfoSxRRCJc', pageUrl: next }), watch);
  assert.equal(clickedYouTube({ pageUrl: watch }), watch);
  assert.equal(clickedYouTube({}, { url: watch }), watch);
  assert.throws(() => clickedYouTube({ linkUrl: 'https://youtube.com/@channel', pageUrl: watch }));
});

const manifest = JSON.parse(readFileSync(new URL('../chrome-extension/extension/manifest.json', import.meta.url)));
test('stable extension identity agrees with native allowlist; icon frames exactly match EXE', () => {
  const id = [...createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0, 32)]
    .map(digit => String.fromCharCode(97 + parseInt(digit, 16))).join('');
  const source = readFileSync(new URL('../native/BrowserIntegration.cs', import.meta.url), 'utf8');
  assert.ok(source.includes(`ExtensionId = "${id}"`));
  const independentHost = readFileSync(new URL('../chrome-native-host/NativeHost.cs', import.meta.url), 'utf8');
  assert.ok(independentHost.includes(`ExtensionId = "${id}"`));
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.host_permissions, undefined);
  const ico = readFileSync(new URL('../native/Assets/Icon/TurnTabler.ico', import.meta.url));
  for (const size of [16, 32, 48, 128]) {
    const png = readFileSync(new URL(`../chrome-extension/extension/icons/${size}.png`, import.meta.url));
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
    let matched = false;
    for (let i = 0; i < ico.readUInt16LE(4); i++) {
      const entry = 6 + i * 16;
      if (ico[entry] !== size) continue;
      const offset = ico.readUInt32LE(entry + 12), length = ico.readUInt32LE(entry + 8);
      assert.deepEqual(png, ico.subarray(offset, offset + length));
      matched = true;
    }
    assert.ok(matched);
  }
});

const calls = [];
let nativeReply = { ok: true };
let nativeError;
const listeners = {};
globalThis.chrome = {
  runtime: {
    id: 'ebnjhkdpohpgeipkalbfklpfibjadnhd',
    onMessage: { addListener: fn => { listeners.message = fn; } },
    onInstalled: { addListener: fn => { listeners.installed = fn; } },
    onStartup: { addListener: fn => { listeners.startup = fn; } },
    sendNativeMessage: async (...args) => { calls.push(['native', ...args]); if (nativeError) throw nativeError; return nativeReply; }
  },
  contextMenus: {
    removeAll: async () => calls.push(['remove']),
    create: (config, done) => { calls.push(['menu', config]); done(); },
    onClicked: { addListener: fn => { listeners.clicked = fn; } }
  },
  storage: { local: { set: async value => calls.push(['storage', value]) } },
  action: Object.fromEntries(['setBadgeText', 'setBadgeBackgroundColor', 'setTitle'].map(name => [name, async value => calls.push([name, value])])),
  notifications: { create: async (...args) => calls.push(['notification', ...args]) }
};
const { createMenu, playClicked, receiveYouTubeMessage } = await import('../chrome-extension/extension/background.mjs');

test('service worker recreates YouTube menu and sends selected URL to native host', async () => {
  calls.length = 0;
  await createMenu();
  assert.equal(calls[0][0], 'remove');
  assert.ok(calls[1][1].contexts.includes('link'));
  assert.ok(calls[1][1].contexts.includes('video'));
  assert.ok(listeners.installed && listeners.startup && listeners.clicked);
  await playClicked({ menuItemId: 'play-in-turntabler', linkUrl: `${watch}&list=RD2qfoSxRRCJc` });
  assert.deepEqual(calls.find(c => c[0] === 'native'), ['native', 'com.turntabler.player', { action: 'play', url: `${watch}&list=RD2qfoSxRRCJc` }]);
  assert.equal(calls.find(c => c[0] === 'storage')[1].lastResult.ok, true);
});

test('invalid links never reach the app; native failures are visible and success clears badge', async () => {
  calls.length = 0;
  await playClicked({ menuItemId: 'play-in-turntabler', linkUrl: 'https://example.com' });
  assert.equal(calls.some(c => c[0] === 'native'), false);
  assert.ok(calls.some(c => c[0] === 'notification'));
  calls.length = 0;
  nativeError = new Error('Specified native messaging host not found.');
  await playClicked({ menuItemId: 'play-in-turntabler', pageUrl: watch });
  assert.match(calls.find(c => c[0] === 'storage')[1].lastResult.message, /Install.cmd/);
  assert.equal(calls.find(c => c[0] === 'setBadgeText')[1].text, '!');
  nativeError = null;
  calls.length = 0;
  nativeReply = { ok: false, error: '재생 엔진 오류' };
  await playClicked({ menuItemId: 'play-in-turntabler', pageUrl: watch });
  assert.equal(calls.find(c => c[0] === 'storage')[1].lastResult.message, '재생 엔진 오류');
  nativeReply = { ok: true };
  calls.length = 0;
  await playClicked({ menuItemId: 'play-in-turntabler', pageUrl: watch });
  assert.equal(calls.find(c => c[0] === 'setBadgeText')[1].text, '');
  calls.length = 0;
  await playClicked({ menuItemId: 'unrelated', pageUrl: watch });
  assert.equal(calls.length, 0);
});

test('YouTube page menu forwards through the worker; unauthorized senders cannot launch the app', async () => {
  const sender = { id: chrome.runtime.id, tab: { id: 7 }, url: watch };
  calls.length = 0;
  const reply = await new Promise(resolve => {
    assert.equal(receiveYouTubeMessage({ type: 'turntabler:play', url: `${watch}&list=RD2qfoSxRRCJc` }, sender, resolve), true);
  });
  assert.equal(reply.ok, true);
  assert.deepEqual(calls.find(c => c[0] === 'native'), ['native', 'com.turntabler.player', { action: 'play', url: `${watch}&list=RD2qfoSxRRCJc` }]);
  for (const invalid of [
    { ...sender, id: 'another-extension' }, { ...sender, url: 'https://youtube.com.evil.org/watch?v=2qfoSxRRCJc' },
    { ...sender, url: 'file:///C:/test.html' }, { ...sender, tab: undefined }, { ...sender, url: undefined }
  ]) {
    calls.length = 0;
    const denied = await new Promise(resolve => assert.equal(receiveYouTubeMessage({ type: 'turntabler:play', url: watch }, invalid, resolve), false));
    assert.equal(denied.ok, false);
    assert.equal(calls.some(c => c[0] === 'native'), false);
  }
  calls.length = 0;
  const invalidLink = await new Promise(resolve => receiveYouTubeMessage({ type: 'turntabler:play', url: 'https://example.com/' }, sender, resolve));
  assert.equal(invalidLink.ok, false);
  assert.equal(calls.some(c => c[0] === 'native'), false);
  assert.equal(receiveYouTubeMessage({ type: 'unrelated' }, sender, () => assert.fail('Unexpected reply')), false);
});
