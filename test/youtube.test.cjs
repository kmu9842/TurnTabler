const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseYouTube } = require('../ui/youtube.js');
const { startServer } = require('../server.cjs');
test('video formats and time offsets', () => {
  for (const url of ['https://youtu.be/dQw4w9WgXcQ', 'youtube.com/watch?v=dQw4w9WgXcQ', 'https://m.youtube.com/shorts/dQw4w9WgXcQ', 'https://www.youtube.com/live/dQw4w9WgXcQ']) assert.equal(parseYouTube(url).video, 'dQw4w9WgXcQ');
  assert.equal(parseYouTube('youtu.be/dQw4w9WgXcQ?t=1h2m3s').start, 3723);
});
test('playlist takes priority and keeps index', () => {
  const data = parseYouTube('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1234567890&index=3');
  assert.equal(data.list, 'PL1234567890'); assert.equal(data.index, 2);
  assert.equal(parseYouTube('youtube.com/playlist?list=PL1234567890').video, null);
});
test('rejects unrelated hosts and malformed links', () => {
  for (const url of ['https://youtube.com.evil.org/watch?v=dQw4w9WgXcQ', 'https://example.com', 'youtube.com/watch?v=bad', 'youtube.com/playlist?list=bad']) assert.throws(() => parseYouTube(url));
});
test('local server serves UI with referrer and restricts paths', async () => {
  const { server, url } = await startServer();
  try { const response = await fetch(url); assert.equal(response.status, 200); assert.match(await response.text(), /TurnTabler/); assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin'); assert.equal((await fetch(url + '/main.cjs')).status, 404); }
  finally { server.close(); }
});
