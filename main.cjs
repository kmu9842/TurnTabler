const { app, BrowserWindow, ipcMain, screen, shell } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const { startServer } = require('./server.cjs');
if (process.env.TURNTABLER_SMOKE === '1') app.setPath('userData', path.join(app.getPath('temp'), 'turntabler-smoke'));
let win, server;
let preferences = {};
const preferencesPath = path.join(app.getPath('userData'), 'preferences.json');
try { preferences = JSON.parse(fs.readFileSync(preferencesPath, 'utf8')); } catch {}
let corner = 'bottom-right';
function dock() {
  const area = screen.getDisplayMatching(win.getBounds()).workArea;
  const [width, height] = win.getSize();
  win.setPosition(corner.endsWith('right') ? area.x + area.width - width - 16 : area.x + 16,
    corner.startsWith('bottom') ? Math.max(area.y, area.y + area.height - height - 16) : area.y + 16);
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { win?.show(); win?.focus(); });
  app.whenReady().then(async () => {
    const local = await startServer(); server = local.server;
    const area = screen.getPrimaryDisplay().workArea;
    win = new BrowserWindow({ width: 460, height: 430, x: area.x + area.width - 476, y: Math.max(area.y, area.y + area.height - 446),
      frame: false, thickFrame: false, hasShadow: false, roundedCorners: false, transparent: true, backgroundColor: '#00000000', resizable: false, alwaysOnTop: true,
      show: false, autoHideMenuBar: true, webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false } });
    win.webContents.setWindowOpenHandler(({ url }) => {
      if (/^https:\/\/(www\.)?(youtube\.com|youtu\.be)\//.test(url)) shell.openExternal(url);
      return { action: 'deny' };
    });
    win.webContents.on('will-navigate', (event, url) => { if (!url.startsWith(local.url + '/')) event.preventDefault(); });
    ipcMain.on('window:close', () => win.close());
    ipcMain.on('window:minimize', () => win.minimize());
    ipcMain.on('preferences:get', event => { event.returnValue = preferences; });
    ipcMain.on('preferences:save', (event, value) => {
      if (event.sender !== win.webContents || !value || typeof value !== 'object') return;
      preferences = { settings: value.settings, url: typeof value.url === 'string' ? value.url.slice(0,2000) : '' };
      fs.mkdirSync(path.dirname(preferencesPath), { recursive: true });
      fs.writeFileSync(preferencesPath, JSON.stringify(preferences), 'utf8');
    });
    ipcMain.handle('window:pin', (_, value) => { win.setAlwaysOnTop(Boolean(value)); return win.isAlwaysOnTop(); });
    ipcMain.handle('window:resize', (_, value) => { const scale = [.8,1,1.2].includes(value) ? value : 1; win.webContents.setZoomFactor(scale); win.setSize(Math.round(460 * scale), Math.round(430 * scale)); dock(); });
    ipcMain.handle('window:corner', (_, value) => { if (['bottom-right','bottom-left','top-right','top-left'].includes(value)) corner = value; dock(); });
    ipcMain.handle('video:frame', async (event, rect) => {
      if (event.sender !== win.webContents) return null;
      const frame = win.webContents.mainFrame.frames.find(value => /^https:\/\/www\.youtube\.com\/embed\//.test(value.url));
      if (frame) {
        try {
          const result = await frame.executeJavaScript(`(() => {
            if (!document.getElementById('turntabler-no-captions')) { const style=document.createElement('style');style.id='turntabler-no-captions';style.textContent='.ytp-caption-window-container,.caption-window{display:none!important}';document.head.append(style); }
            const embedded=document.getElementById('movie_player');try { embedded?.unloadModule('captions'); } catch {}
            const video = document.querySelector('video');
            if (!video || !video.videoWidth || video.readyState < 2) return null;
            const canvas = document.createElement('canvas'); canvas.width = 48; canvas.height = 27;
            canvas.getContext('2d').drawImage(video,0,0,48,27);
            return { image:canvas.toDataURL('image/png'), aspect:video.videoWidth/video.videoHeight };
          })()`);
          if (result && /^data:image\/png;base64,/.test(result.image) && result.image.length < 24000 && result.aspect > .1 && result.aspect < 10) return result;
        } catch {}
      }
      if (!rect || !['x','y','width','height'].every(key => Number.isFinite(rect[key]))) return null;
      const zoom = win.webContents.getZoomFactor(), bounds = win.getContentBounds();
      const region = Object.fromEntries(Object.entries(rect).map(([key,value]) => [key,Math.round(value * zoom)]));
      if (region.width < 1 || region.height < 1 || region.x < 0 || region.y < 0 || region.x+region.width > bounds.width || region.y+region.height > bounds.height) return null;
      return { image:(await win.webContents.capturePage(region)).resize({width:48,height:27}).toDataURL(), aspect:16/9 };
    });
    ipcMain.handle('video:palette', async (event, rect) => {
      if (event.sender !== win.webContents || !rect || !['x','y','width','height'].every(key => Number.isFinite(rect[key]))) return null;
      const bounds = win.getContentBounds(), zoom = win.webContents.getZoomFactor();
      const region = Object.fromEntries(Object.entries(rect).map(([key, value]) => [key, Math.round(value * zoom)]));
      if (region.width < 1 || region.height < 1 || region.x < 0 || region.y < 0 || region.x + region.width > bounds.width || region.y + region.height > bounds.height) return null;
      const image = await win.webContents.capturePage(region), bitmap = image.toBitmap(), size = image.getSize();
      const sums = Array.from({ length: 3 }, () => [0,0,0,0]);
      for (let y = 0; y < size.height; y += 3) for (let x = 0; x < size.width; x += 3) {
        const offset = (y * size.width + x) * 4, b = bitmap[offset], g = bitmap[offset+1], r = bitmap[offset+2];
        if (Math.max(r,g,b) < 22) continue;
        const sum = sums[Math.min(2, Math.floor(x / size.width * 3))]; sum[0] += r; sum[1] += g; sum[2] += b; sum[3]++;
      }
      return sums.map(sum => { if (!sum[3]) return [70,100,150]; const avg = sum.slice(0,3).map(value => value / sum[3]), max = Math.max(...avg), min = Math.min(...avg); return avg.map(value => Math.round(Math.max(0,Math.min(255,(value-min) * 1.25 + min + Math.max(0,105-max))))); });
    });
    win.once('ready-to-show', () => { if (process.env.TURNTABLER_SMOKE !== '1') win.show(); });
    await win.loadURL(local.url);
    if (process.argv.includes('--demo')) {
      let attempts = 0;
      const timer = setInterval(async () => {
        try {
          if (!await win.webContents.executeJavaScript('typeof ready !== "undefined" && ready')) { if (++attempts > 60) clearInterval(timer); return; }
          clearInterval(timer);
          await win.webContents.executeJavaScript('settings.volume=15;applySettings();document.getElementById("url").value="https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=40";document.getElementById("link-form").requestSubmit();void 0');
          if (process.argv.includes('--capture-demo')) setTimeout(async () => {
            if (win.isDestroyed()) return;
            const output = path.join(process.env.PORTABLE_EXECUTABLE_DIR || __dirname, 'artifacts');
            fs.mkdirSync(output, { recursive: true });
            fs.writeFileSync(path.join(output, 'desktop-use.png'), (await win.webContents.capturePage()).toPNG());
            fs.writeFileSync(path.join(output, 'desktop-state.json'), JSON.stringify({ visible:win.isVisible(), alwaysOnTop:win.isAlwaysOnTop(), bounds:win.getBounds(), workArea:screen.getDisplayMatching(win.getBounds()).workArea, renderer:await win.webContents.executeJavaScript('({playing:player.getPlayerState()===1,record:getComputedStyle(document.querySelector(".vinyl")).animationPlayState,rotationDuration:getComputedStyle(document.querySelector(".vinyl")).animationDuration,inputMargin:getComputedStyle(document.getElementById("link-form")).marginTop,artReady:document.body.classList.contains("art-ready"),ambient:document.querySelector(".video-wash").style.backgroundImage.length})') },null,2));
          }, 16000);
        } catch { clearInterval(timer); }
      }, 500);
    }
  });
  app.on('window-all-closed', () => { server?.close(); app.quit(); });
}
