const { app } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
process.env.TURNTABLER_SMOKE = '1';
require('../main.cjs');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
app.on('browser-window-created', (_, win) => {
  win.webContents.on('console-message', event => { if (event.level === 'error') console.log('Renderer: ' + event.message); });
  win.webContents.once('did-finish-load', async () => {
    const js = value => win.webContents.executeJavaScript(value);
    const report = {};
    async function until(expression, limit = 20000) {
      const end = Date.now() + limit;
      while (Date.now() < end) { if (await js(expression)) return; await sleep(500); }
      throw new Error('Timed out: ' + expression);
    }
    async function capture(name) {
      fs.mkdirSync(path.join(__dirname, '../artifacts'), {recursive:true});
      fs.writeFileSync(path.join(__dirname, '../artifacts/' + name + '.png'), (await win.webContents.capturePage()).toPNG());
    }
    try {
      win.showInactive();
      await until('ready && document.querySelector(".deck-image").naturalWidth === 1536 && document.body.classList.contains("art-ready")');
      report.initial = await js('({transparent:getComputedStyle(document.body).backgroundColor,buttons:document.querySelectorAll("#link-form button").length,image:document.querySelector(".deck-image").naturalWidth,settingsHidden:document.getElementById("settings").hidden})');
      if (report.initial.transparent !== 'rgba(0, 0, 0, 0)' || report.initial.buttons !== 2) throw new Error('Initial layout failed');
      report.glass=await js('(()=>{const c=document.querySelector(".art-base"),ctx=c.getContext("2d");const d=ctx.getImageData(1340,540,60,100).data;let maxAlpha=0;for(let i=3;i<d.length;i+=4)maxAlpha=Math.max(maxAlpha,d[i]);const edge=ctx.getImageData(1460,480,1,1).data[3];return {maxInteriorAlpha:maxAlpha,edgeAlpha:edge}})()');
      if(report.glass.maxInteriorAlpha>15 || report.glass.edgeAlpha<40)throw new Error('Glass matte is not transparent or the body was lost');
      await js('document.body.style.backgroundColor="#526778"');await capture('glass-on-background');await js('document.body.style.backgroundColor="transparent"');
      await capture('widget');
      await js('settings.volume=0;applySettings();document.getElementById("url").value="https://www.youtube.com/watch?v=aqz-KE-bpKQ";document.getElementById("link-form").requestSubmit()');
      await until('player.getPlayerState() === 1');
      await sleep(3000);
      await js('player.seekTo(40,true);void 0'); await sleep(6500);
      const first = await js('getComputedStyle(document.querySelector(".vinyl")).transform');
      await sleep(350);
      const second = await js('getComputedStyle(document.querySelector(".vinyl")).transform');
      report.playback = await js('({state:player.getPlayerState(),video:player.getVideoData().video_id,rotation:getComputedStyle(document.querySelector(".vinyl")).animationPlayState,ambient:document.querySelector(".video-wash").style.backgroundImage.length})');
      report.rotationMoved = first !== second;
      if (!report.rotationMoved) throw new Error('Record did not rotate');
      await until('document.body.classList.contains("fader-ready")');
      report.cover = await js('({disk:document.querySelector(".projection").clientWidth,width:document.getElementById("player").offsetWidth,height:document.getElementById("player").offsetHeight,inset:getComputedStyle(document.querySelector(".projection")).top,marker:getComputedStyle(document.querySelector(".vinyl i")).display})');
      if(report.cover.width<report.cover.disk || report.cover.height<report.cover.disk || report.cover.inset!=='0px' || report.cover.marker!=='none') throw new Error('Video cover or marker failed');
      await js('document.getElementById("deck-volume").value=23;document.getElementById("deck-volume").dispatchEvent(new Event("input"));void 0');
      await until('player.getVolume()===23');report.volume=23;
      const embed=win.webContents.mainFrame.frames.find(f=>f.url.startsWith('https://www.youtube.com/embed/'));
      report.captionsHidden=await embed.executeJavaScript('!!document.getElementById("turntabler-no-captions") && [...document.querySelectorAll(".ytp-caption-window-container")].every(e=>getComputedStyle(e).display==="none")');
      if(!report.captionsHidden) throw new Error('Caption hiding failed');
      await capture('playing');
      await js('document.getElementById("video-hit").click()');
      await until('player.getPlayerState()===2');
      if (await js('getComputedStyle(document.querySelector(".vinyl")).animationPlayState') !== 'paused') throw new Error('Pause failed');
      await js('document.getElementById("settings-toggle").click()');
      report.settings = await js('({hidden:document.getElementById("settings").hidden,bottom:document.getElementById("settings").getBoundingClientRect().bottom,height:innerHeight})');
      if (report.settings.hidden || report.settings.bottom > report.settings.height) throw new Error('Settings clipped');
      await capture('settings');
      await js('document.getElementById("effect").click();document.getElementById("rotation").click()');
      if (!await js('document.body.classList.contains("no-effect") && document.body.classList.contains("no-rotation")')) throw new Error('Settings toggles failed');
      await js('document.getElementById("effect").click();document.getElementById("rotation").click();document.getElementById("settings-close").click();document.getElementById("url").value="https://www.youtube.com/playlist?list=PLNYkxOF6rcIDfz8XEA3loxY32tYh7CI3m";document.getElementById("link-form").requestSubmit()');
      await until('(player.getPlaylist()||[]).length > 1', 25000);
      await sleep(1500);
      report.playlist = await js('({length:player.getPlaylist().length,index:player.getPlaylistIndex(),previous:document.getElementById("previous").disabled,next:document.getElementById("next").disabled})');
      await js('document.getElementById("next").click()');
      await until('player.getPlaylistIndex() === 1');
      await js('document.getElementById("previous").click()');
      await until('player.getPlaylistIndex() === 0');
      report.playlistNavigation = true;
      await js('document.getElementById("settings-toggle").click()');
      await capture('playlist');
      const prefs = JSON.parse(fs.readFileSync(path.join(app.getPath('userData'),'preferences.json'),'utf8'));
      if (!prefs.url.includes('PLNYkxOF6rcIDfz8XEA3loxY32tYh7CI3m')) throw new Error('Preference persistence failed');
      report.preferencesSaved = true;
      fs.writeFileSync(path.join(__dirname,'../artifacts/verification.json'), JSON.stringify(report,null,2));
      console.log(JSON.stringify(report));
      app.quit();
    } catch (error) { console.error(error); console.log(JSON.stringify(report)); app.exit(1); }
  });
});
setTimeout(() => app.exit(1), 90000);
