import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

// Invoke through test-chrome.ps1, which isolates installer files and restores registry values.
const [output, extension] = process.argv.slice(2);
if (!output || !extension) throw new Error('Run scripts/test-chrome.ps1');
const chrome = process.env.TURNTABLER_TEST_CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const child = spawn(chrome, [
  '--headless=new', '--no-first-run', '--no-default-browser-check', '--mute-audio', '--remote-debugging-pipe',
  '--enable-unsafe-extension-debugging', '--user-data-dir=' + path.join(output, 'chrome-profile')
], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
let pending = '', sequence = 0, widgetPid, youtubeSession, workerSession;
const callbacks = new Map();
const stderr = [];
child.stderr.on('data', data => stderr.push(data));
child.stdio[3].on('error', () => {});
child.stdio[4].on('data', data => {
  pending += data.toString();
  let end;
  while ((end = pending.indexOf('\0')) !== -1) {
    const message = JSON.parse(pending.slice(0, end)); pending = pending.slice(end + 1);
    const callback = callbacks.get(message.id);
    if (!callback) continue;
    callbacks.delete(message.id); clearTimeout(callback.timer);
    if (message.error) callback.reject(new Error(JSON.stringify(message.error)));
    else callback.resolve(message.result);
  }
});
function command(method, params = {}, sessionId) {
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { callbacks.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 50000);
    callbacks.set(id, { resolve, reject, timer });
    child.stdio[3].write(JSON.stringify({ id, method, params, sessionId }) + '\0');
  });
}
async function evaluate(session, expression) {
  const result = await command('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, session);
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
async function until(action, description, milliseconds = 75000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    const error = await readFile(path.join(output, 'browser-failure.json'), 'utf8').catch(() => null);
    if (error) throw new Error(error);
    const value = await action(); if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 400));
  }
  throw new Error(`Timeout: ${description}`);
}
const loadReport = name => readFile(path.join(output, name), 'utf8').then(JSON.parse).catch(() => null);

async function mouse(session, x, y, button = 'left') {
  await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }, session);
  await command('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button, buttons: button === 'right' ? 2 : 1, clickCount: 1 }, session);
  await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button, buttons: 0, clickCount: 1 }, session);
}

async function openYouTubeMenu(session) {
  const point = await until(() => evaluate(session, `(() => {
    const player = document.querySelector('#movie_player');
    if (!player?.querySelector('.ytp-chrome-controls')) return null;
    // YouTube's loading surface can briefly cover a menu opened during navigation.
    const video = player.querySelector('video');
    if (!video || video.readyState < 2 || ![1, 2].includes(player.getPlayerState?.())) return null;
    const r = player.getBoundingClientRect(), x = r.x + Math.min(400, r.width / 2), y = r.y + Math.min(180, r.height / 2);
    const target = document.elementFromPoint(x, y);
    return r.width > 200 && r.height > 150 && player.contains(target) && !target?.closest('.ytp-contextmenu') ? {x, y} : null;
  })()`), 'YouTube player ready', 60000);
  await mouse(session, point.x, point.y, 'right');
  await until(() => evaluate(session, `(() => {
    const item = document.querySelector('.ytp-contextmenu .turntabler-youtube-item');
    return !!item && item.getBoundingClientRect().height > 10 && item.querySelector('img').naturalWidth === 32;
  })()`), 'TurnTabler in YouTube own right-click menu', 15000);
  return evaluate(session, `(() => {
    const menu = document.querySelector('.ytp-contextmenu.turntabler-youtube-menu'), r = menu.getBoundingClientRect();
    const items = [...menu.querySelectorAll('.ytp-menuitem')].filter(e => e.getBoundingClientRect().height > 0);
    return { count: menu.querySelectorAll('.turntabler-youtube-item').length,
      first: items[0]?.textContent, originalItems: items.length - 1,
      fits: items.every(e => { const b = e.getBoundingClientRect(); return b.top >= r.top - 1 && b.bottom <= r.bottom + 1; }),
      inViewport: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth,
      screenshot: { x: r.x, y: r.y, width: r.width, height: r.height, scale: 1 } };
  })()`);
}

async function clickYouTubeItem(session) {
  await evaluate(session, 'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
  const point = await until(() => evaluate(session, `(() => {
    const item = document.querySelector('.turntabler-youtube-item');
    if (!item) return null;
    const r = item.getBoundingClientRect(), x = r.x+r.width/2, y = r.y+r.height/2;
    return r.height > 10 && document.elementFromPoint(x, y)?.closest('.turntabler-youtube-item') === item ? {x, y} : null;
  })()`), 'YouTube menu row is visible and clickable', 15000);
  assert.ok(await evaluate(session, `!!document.elementFromPoint(${point.x}, ${point.y})?.closest('.turntabler-youtube-item')`), 'Menu row must be the visible click target');
  await mouse(session, point.x, point.y);
  await until(async () => {
    const result = await evaluate(session, "({ message: document.querySelector('#turntabler-playback-notice')?.textContent, error: document.querySelector('#turntabler-playback-notice')?.dataset.error })");
    if (result.error === 'true') throw new Error(result.message);
    return result.message === 'TurnTabler에 재생 요청을 전달했습니다.';
  }, 'YouTube menu click delivered playback');
}

async function closeYouTubeMenu(session) {
  await command('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }, session);
  await command('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }, session);
  await until(() => evaluate(session, "![...document.querySelectorAll('.ytp-contextmenu')].some(e => e.getBoundingClientRect().height > 0)"), 'YouTube menu closed', 5000);
  await evaluate(session, 'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
}

async function navigateVideo(session, url) {
  const oldDocument = await evaluate(session, 'performance.timeOrigin');
  await command('Page.navigate', { url }, session);
  await until(async () => {
    try { return await evaluate(session, `new URL(location.href).searchParams.get('v') === ${JSON.stringify(new URL(url).searchParams.get('v'))} && performance.timeOrigin !== ${oldDocument} && document.readyState !== 'loading'`); }
    catch (error) { if (/context|navigat/i.test(error.message)) return false; throw error; }
  }, 'new YouTube document loaded');
}

try {
  const version = await command('Browser.getVersion');
  const { id } = await command('Extensions.loadUnpacked', { path: extension });
  assert.equal(id, 'ebnjhkdpohpgeipkalbfklpfibjadnhd');
  const worker = await until(async () => (await command('Target.getTargets')).targetInfos.find(t => t.type === 'service_worker' && t.url.startsWith(`chrome-extension://${id}/`)), 'extension service worker');
  const { sessionId } = await command('Target.attachToTarget', { targetId: worker.targetId, flatten: true });
  workerSession = sessionId;
  await command('Runtime.enable', {}, sessionId);
  await until(() => evaluate(sessionId, "typeof chrome !== 'undefined' && typeof chrome.runtime?.sendNativeMessage === 'function'"), 'extension APIs ready', 20000);
  const native = request => evaluate(sessionId, `chrome.runtime.sendNativeMessage('com.turntabler.player', ${JSON.stringify(request)})`);
  assert.equal((await native({ action: 'ping' })).ok, true);
  await until(() => evaluate(sessionId, "new Promise(resolve => chrome.contextMenus.update('play-in-turntabler', {enabled:true}, () => resolve(!chrome.runtime.lastError)))"), 'context menu registration', 20000);
  assert.equal((await native({ action: 'play', url: 'https://example.com' })).ok, false);
  console.log('PASS: real Chrome loaded extension, registered context menu, native host ping and URL validation');
  const initialSettings = await native({ action: 'getSettings' });
  const settingsPage = await command('Target.createTarget', { url: `chrome-extension://${id}/options.html` });
  const settings = (await command('Target.attachToTarget', { targetId: settingsPage.targetId, flatten: true })).sessionId;
  await until(() => evaluate(settings, "document.querySelector('#status')?.dataset.ok === 'true'"), 'settings loaded');
  assert.equal(await evaluate(settings, "document.querySelector('#app-path').value"), initialSettings.appPath);
  const savePath = async appPath => {
    await evaluate(settings, `document.querySelector('#app-path').value = ${JSON.stringify(appPath)}; document.querySelector('#save').click()`);
    await until(() => evaluate(settings, "!document.querySelector('#save').disabled"), 'settings saved');
  };
  await savePath('C:\\missing\\TurnTabler.exe');
  assert.equal(await evaluate(settings, "document.querySelector('#status').dataset.ok"), 'false');
  assert.equal((await native({ action: 'getSettings' })).appPath, initialSettings.appPath);
  const releasedPath = path.resolve(import.meta.dirname, '../release/single-file/TurnTabler.exe');
  await savePath(releasedPath);
  assert.equal(await evaluate(settings, "document.querySelector('#status').dataset.ok"), 'true');
  assert.match(await evaluate(settings, "document.querySelector('#version').textContent"), /1\.0\.0\.0/);
  assert.equal((await native({ action: 'getSettings' })).appPath, releasedPath);
  await command('Page.reload', {}, settings);
  await until(() => evaluate(settings, "document.querySelector('#status')?.dataset.ok === 'true'"), 'settings persisted after reload');
  assert.equal(await evaluate(settings, "document.querySelector('#app-path').value"), releasedPath);
  const optionsScreenshot = await command('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1000, height: 750, scale: 1 } }, settings);
  await writeFile(path.join(output, 'extension-settings.png'), Buffer.from(optionsScreenshot.data, 'base64'));
  await savePath(initialSettings.appPath);
  await command('Target.closeTarget', { targetId: settingsPage.targetId });
  console.log('PASS: real Chrome settings path change to distributed 1.0.0, version display, invalid path rejection and reload persistence');
  const youtube = await command('Target.createTarget', { url: 'about:blank' });
  youtubeSession = (await command('Target.attachToTarget', { targetId: youtube.targetId, flatten: true })).sessionId;
  await command('Page.enable', {}, youtubeSession);
  await command('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }, youtubeSession);
  await navigateVideo(youtubeSession, 'https://www.youtube.com/watch?v=2qfoSxRRCJc&list=RD2qfoSxRRCJc&index=1');
  const menu = await openYouTubeMenu(youtubeSession);
  assert.equal(menu.count, 1); assert.match(menu.first, /TurnTabler/);
  assert.ok(menu.originalItems >= 5 && menu.fits && menu.inViewport, JSON.stringify(menu));
  assert.ok(menu.screenshot.width >= 220 && menu.screenshot.width < 450, 'Menu must keep a compact width: ' + JSON.stringify(menu));
  const menuScreenshot = await command('Page.captureScreenshot', { format: 'png', clip: menu.screenshot }, youtubeSession);
  await writeFile(path.join(output, 'youtube-context-menu.png'), Buffer.from(menuScreenshot.data, 'base64'));
  // Page JavaScript cannot trigger app launches by clicking the injected DOM row.
  await evaluate(youtubeSession, "document.querySelector('.turntabler-youtube-item').click()");
  assert.equal((await evaluate(sessionId, "chrome.storage.local.get('lastResult')")).lastResult, undefined);
  // Reopening and a YouTube menu rebuild must not duplicate or lose the item.
  await closeYouTubeMenu(youtubeSession);
  const reopened = await openYouTubeMenu(youtubeSession); assert.equal(reopened.count, 1);
  await evaluate(youtubeSession, "document.querySelector('.turntabler-youtube-item').remove()");
  await until(() => evaluate(youtubeSession, "document.querySelectorAll('.ytp-contextmenu .turntabler-youtube-item').length === 1"), 'menu row rebuilt');
  await closeYouTubeMenu(youtubeSession);
  await openYouTubeMenu(youtubeSession);
  await clickYouTubeItem(youtubeSession);
  const ready = await until(() => loadReport('browser-ready.json'), 'first playback');
  widgetPid = ready.processId; assert.ok(ready.hidden);
  console.log(`PASS: YouTube own menu click started TurnTabler and played video (PID ${widgetPid})`);
  assert.equal((await openYouTubeMenu(youtubeSession)).count, 1, 'Menu must reopen normally after sending playback');
  await navigateVideo(youtubeSession, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43');
  assert.equal((await openYouTubeMenu(youtubeSession)).count, 1);
  await clickYouTubeItem(youtubeSession);
  const report = await until(() => loadReport('browser-verification.json'), 'second playback');
  assert.equal(report.processId, widgetPid);
  assert.ok(report.success && report.playing && report.hiddenWidgetRestored);

  const page = await command('Target.createTarget', { url: `chrome-extension://${id}/popup.html` });
  const popup = await command('Target.attachToTarget', { targetId: page.targetId, flatten: true });
  await until(() => evaluate(popup.sessionId, "document.querySelector('#status')?.dataset.ok === 'true'"), 'popup connection check', 20000);
  const screenshot = await command('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 350, height: 490, scale: 1 } }, popup.sessionId);
  await writeFile(path.join(output, 'extension-popup.png'), Buffer.from(screenshot.data, 'base64'));
  const result = { ...report, chrome: version.product, extensionId: id, contextMenu: true, youtubeOwnMenu: true,
    youtubeMenuReopened: true, youtubeMenuRebuilt: true, syntheticClicksRejected: true,
    nativeHost: true, popupConnected: true, settingsPathReset: true, settingsRejectInvalidPath: true, menu };
  await writeFile(path.join(output, 'chrome-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  console.log(`Artifacts: ${output}`);
  await new Promise(resolve => setTimeout(resolve, 1800));
} catch (error) {
  if (workerSession) {
    try { await writeFile(path.join(output, 'extension-failure.json'), JSON.stringify(await evaluate(workerSession, "chrome.storage.local.get('lastResult')"), null, 2)); } catch { }
  }
  if (youtubeSession) {
    try {
      const failure = await command('Page.captureScreenshot', { format: 'png' }, youtubeSession);
      await writeFile(path.join(output, 'youtube-failure.png'), Buffer.from(failure.data, 'base64'));
      const layout = await evaluate(youtubeSession, `(() => {
        const menu = document.querySelector('.ytp-contextmenu');
        return { url: location.href, notice: document.querySelector('#turntabler-playback-notice')?.textContent, error: ${JSON.stringify('YouTube menu test failed')}, menu: menu?.outerHTML,
          layout: [menu, ...document.querySelectorAll('.ytp-contextmenu .ytp-popup-content, .ytp-contextmenu .ytp-panel, .ytp-contextmenu .ytp-panel-menu')].filter(Boolean).map(e => {
            const s = getComputedStyle(e); return {class: e.className, rect: e.getBoundingClientRect().toJSON(), position:s.position, height:s.height, display:s.display, overflow:s.overflow};
          }) };
      })()`);
      await writeFile(path.join(output, 'youtube-failure.json'), JSON.stringify(layout, null, 2));
    } catch { }
  }
  throw error;
} finally {
  try { await command('Browser.close'); } catch { child.kill(); }
  if (widgetPid) { try { process.kill(widgetPid); } catch {} }
  await writeFile(path.join(output, 'chrome-stderr.log'), Buffer.concat(stderr));
  for (const { timer, reject } of callbacks.values()) { clearTimeout(timer); reject(new Error('Chrome closed')); }
  callbacks.clear();
}
