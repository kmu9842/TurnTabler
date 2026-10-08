(() => {
  if (window !== window.top || location.hostname !== 'www.youtube.com') return;
  const style = document.createElement('style');
  style.id = 'turntabler-widget-style';
  style.textContent = `
    html.tt-widget,html.tt-widget body{margin:0!important;overflow:hidden!important;background:#111!important}
    html.tt-widget body *:not(#movie_player):not(#movie_player *){visibility:hidden!important}
    html.tt-widget #movie_player{visibility:visible!important}
    html.tt-widget #movie_player{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;min-width:0!important;min-height:0!important;z-index:2147483000!important;margin:0!important;border-radius:0!important}
    html.tt-widget .html5-video-container{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;transform:none!important}
    html.tt-widget video.html5-main-video{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;object-fit:cover!important;object-position:50% 50%!important;transform:none!important;margin:0!important}
    html.tt-widget .ytp-chrome-top,html.tt-widget .ytp-chrome-bottom,html.tt-widget .ytp-gradient-top,html.tt-widget .ytp-gradient-bottom{visibility:hidden!important;display:none!important}
    html.tt-widget:not(.tt-captions) .ytp-caption-window-container{visibility:hidden!important;display:none!important}
  `;
  let widget = window.__turntablerInitialWidgetMode ?? true, volume = Number(window.__turntablerInitialVolume ?? 65);
  let desiredPlaying = true, playUntil = Date.now() + 12000, playAttempt = 0, lastVideo;
  let epoch = '', endedAt = 0, transition = null, failedEpoch = '', navigatingAt = 0;
  let skipButton = null, skipAttempts = 0, skipAttemptAt = 0, nativeSkipRequested = false;
  let wasAd = false, skippedAds = 0, userActionAt = 0;
  const readOutput = () => { try { return localStorage.getItem('turntabler.outputDevice') ?? window.__turntablerInitialOutputDevice ?? ''; } catch { return window.__turntablerInitialOutputDevice || ''; } };
  let outputDevice = String(readOutput()), outputAttempt = '', outputApplying = false;
  const rememberOutput = () => { try { localStorage.setItem('turntabler.outputDevice', outputDevice); } catch {} };
  let captions = !!window.__turntablerInitialCaptions, captionAttempt = 0, playlistStarted = false;
  const player = () => document.getElementById('movie_player');
  const video = () => document.querySelector('video.html5-main-video') || document.querySelector('video');
  const visible = element => {
    if (!element || !element.isConnected) return false;
    const css = getComputedStyle(element);
    return css.display !== 'none' && css.visibility !== 'hidden' && element.getClientRects().length > 0;
  };
  const post = state => {
    if (window.chrome?.webview) window.chrome.webview.postMessage(state);
    else window.webkit?.messageHandlers?.turntabler?.postMessage(state);
  };
  const isAd = () => !!player()?.classList?.contains('ad-showing') || !!player()?.classList?.contains('ad-interrupting');
  const enabled = element => !!element && !element.disabled && element.getAttribute('aria-disabled') !== 'true';
  const locationKey = () => { const u = new URL(location.href); return [u.searchParams.get('v'), u.searchParams.get('list'), u.searchParams.get('index')].join(':'); };
  const wantsPlay = () => { desiredPlaying = true; playUntil = Date.now() + 12000; playAttempt = 0; };
  function applyMode() {
    if (!document.documentElement) return;
    if (!style.isConnected) document.documentElement.append(style);
    document.documentElement.classList.toggle('tt-widget', widget && !!player());
    document.documentElement.classList.toggle('tt-captions', captions);
  }
  function setVolume(value) {
    volume = Math.max(0, Math.min(100, Number(value)));
    const p = player(), v = video();
    if (p?.setVolume) { p.setVolume(volume); if (volume > 0) p.unMute?.(); else p.mute?.(); }
    if (v) { v.volume = volume / 100; v.muted = volume === 0; }
  }
  function syncCaptions() {
    const button = document.querySelector('.ytp-subtitles-button');
    if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true') return;
    const pressed = button.getAttribute('aria-pressed');
    if (pressed !== null && (pressed === 'true') !== captions && Date.now() - captionAttempt > 1200) {
      captionAttempt = Date.now(); button.click();
    }
  }
  function playlistTracks() {
    return [...document.querySelectorAll('ytd-playlist-panel-video-renderer')].map((row, index) => {
      const link = row.querySelector('a#wc-endpoint[href], a[href*="watch?"]');
      if (!link) return null;
      const url = new URL(link.href, location.origin), videoId = url.searchParams.get('v');
      if (url.origin !== location.origin || !/^[\w-]{11}$/.test(videoId || '')) return null;
      return {url:url.href, videoId, number:row.querySelector('#index')?.textContent?.trim() || String(index + 1),
        title:row.querySelector('#video-title')?.textContent?.trim() || link.title || videoId,
        selected:row.hasAttribute('selected')};
    }).filter(Boolean);
  }
  function adjacent(direction, tracks = playlistTracks()) {
    const current = new URL(location.href), list = current.searchParams.get('list');
    let index = tracks.findIndex(track => track.selected);
    if (index < 0) index = tracks.findIndex(track => {
      const url = new URL(track.url);
      return track.videoId === current.searchParams.get('v') && (!current.searchParams.get('index') || url.searchParams.get('index') === current.searchParams.get('index'));
    });
    const candidate = index >= 0 ? tracks[index + direction]?.url : null;
    const button = document.querySelector(direction > 0 ? '.ytp-next-button' : '.ytp-prev-button');
    const href = candidate || (enabled(button) && button.getAttribute('href'));
    if (!href) return null;
    try {
      const url = new URL(href, location.origin);
      if (url.origin !== location.origin || url.pathname !== '/watch' || !/^[\w-]{11}$/.test(url.searchParams.get('v') || '')) return null;
      if (list && url.searchParams.get('list') !== list) return null;
      url.searchParams.delete('t'); url.searchParams.delete('start');
      if (url.searchParams.get('v') === current.searchParams.get('v') && url.searchParams.get('index') === current.searchParams.get('index')) return null;
      return url.href;
    } catch { return null; }
  }
  function advance(direction = 1, automatic = false) {
    if (transition || isAd()) return;
    const target = adjacent(direction);
    const hasList = !!new URL(location.href).searchParams.get('list');
    // An automatic transition must remain inside the currently loaded list.
    if (automatic && (!hasList || !target)) return;
    wantsPlay(); endedAt = 0;
    transition = { key: locationKey(), direction, target, stage: 0, at: Date.now() };
    stepTransition();
  }
  function stepTransition() {
    if (!transition || isAd()) return;
    const now = Date.now(), item = transition;
    if (locationKey() !== item.key) { transition = null; wantsPlay(); return; }
    if (navigatingAt && now - navigatingAt < 8000) return;
    if (item.stage > 0 && now - item.at < (item.stage === 3 ? 8000 : 1800)) return;
    item.at = now;
    try {
      if (item.stage++ === 0) {
        const p = player(), method = item.direction > 0 ? 'nextVideo' : 'previousVideo';
        if (typeof p?.[method] === 'function') { p[method](); return; }
      }
      if (item.stage <= 2) {
        item.stage = 2;
        const button = document.querySelector(item.direction > 0 ? '.ytp-next-button' : '.ytp-prev-button');
        if (enabled(button)) { button.click(); return; }
      }
      if (item.stage <= 3 && item.target) {
        item.stage = 3; location.assign(item.target); return;
      }
    } catch (error) { post({type:'diagnostic', event:'next-attempt', message:String(error)}); }
    if (item.stage >= 3 || !item.target) {
      failedEpoch = item.key; transition = null;
      post({type:'notice', message:'다음 곡으로 이동하지 못했습니다. 브라우저에서 재생목록을 확인해 주세요.'});
    }
  }
  function findSkipButton() {
    if (!isAd()) return null;
    const clickable = button => {
      if (!visible(button) || !enabled(button)) return false;
      // A stale skip control can remain in the DOM under the content/overlays.
      // Click only the live element that would receive a click in the page.
      if (typeof document.elementFromPoint !== 'function') return true;
      const r = button.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return false;
      const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return !!hit && (hit === button || button.contains(hit));
    };
    const selectors = '.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button,.ytp-ad-skip-button-container button';
    const exact = [...(player()?.querySelectorAll(selectors) || [])].find(clickable);
    if (exact) return exact;
    return [...(player()?.querySelectorAll('button[aria-label]') || [])].find(button =>
      /^(skip (ad|ads)|광고 건너뛰기|건너뛰기)$/i.test(button.getAttribute('aria-label')?.trim() || '') && clickable(button)) || null;
  }
  function skipAds() {
    const ad = isAd(), button = findSkipButton();
    if (wasAd && !ad && skipAttempts > 0) skippedAds++;
    wasAd = ad;
    if (button !== skipButton) { skipButton = button; skipAttempts = 0; skipAttemptAt = 0; nativeSkipRequested = false; }
    if (!button || Date.now() - skipAttemptAt < 800) return;
    if (skipAttempts < 4) {
      skipAttemptAt = Date.now(); skipAttempts++;
      button.click();
      post({type:'diagnostic', event:'ad-skip-attempt', attempt:skipAttempts});
    } else if (window.__turntablerAllowNativeSkipInput !== false && !nativeSkipRequested) {
      nativeSkipRequested = true;
      post({type:'skip-input'});
    }
  }
  async function listAudioOutputs() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      // WebKit can return an empty/redacted list before the user grants device access.
      const outputsVisible = devices.some(d => d.kind === 'audiooutput' && d.deviceId);
      if (outputDevice && outputsVisible && !devices.some(d => d.kind === 'audiooutput' && d.deviceId === outputDevice)) {
        outputDevice = ''; outputAttempt = ''; rememberOutput(); await applyOutput(true);
        post({type:'audio-output', deviceId:'', ok:true, fallback:true});
      }
      post({type:'audio-devices', devices:devices.filter(d => d.kind === 'audiooutput').map(d => ({id:d.deviceId, name:d.label || '오디오 출력 장치'})), selected:outputDevice});
    } catch (error) { post({type:'audio-error', message:String(error)}); }
  }
  async function applyOutput(force = false) {
    const v = video();
    if (!v || outputApplying) return;
    if (typeof v.setSinkId !== 'function') {
      if (force && outputDevice) post({type:'audio-error', message:'이 재생 엔진에서는 출력 장치를 선택할 수 없습니다. 시스템 기본 출력을 사용합니다.'});
      return;
    }
    if (!force && v.sinkId === outputDevice) return;
    if (!force && outputAttempt === outputDevice + ':' + epoch) return;
    const requested = outputDevice;
    outputApplying = true; outputAttempt = requested + ':' + epoch;
    try {
      await v.setSinkId(requested);
      if (requested === outputDevice) { rememberOutput(); post({type:'audio-output', deviceId:requested, ok:true}); }
    }
    catch (error) {
      if (requested !== outputDevice) return;
      if (error.name === 'NotFoundError') {
        outputDevice = ''; rememberOutput();
        try { await v.setSinkId(''); post({type:'audio-output', deviceId:'', ok:true, fallback:true}); }
        catch (fallbackError) { post({type:'audio-error', message:'기본 출력 장치도 사용할 수 없습니다. ' + fallbackError.message}); }
      } else post({type:'audio-error', message:'출력 장치를 변경하지 못했습니다: ' + error.message});
    } finally { outputApplying = false; if (requested !== outputDevice) { outputAttempt = ''; void applyOutput(true); } }
  }
  window.turntablerNative = {
    setWidgetMode(value) { widget = !!value; applyMode(); },
    setVolume,
    setCaptions(value) { captions = !!value; captionAttempt = 0; applyMode(); syncCaptions(); },
    toggle() { const v = video(); if (v) { if (v.paused) { wantsPlay(); v.play().catch(() => post({type:'notice', message:'브라우저에서 재생을 눌러 주세요.'})); } else { desiredPlaying = false; playUntil = 0; transition = null; v.pause(); } } },
    play() { wantsPlay(); video()?.play().catch(() => {}); },
    pause() { desiredPlaying = false; playUntil = 0; transition = null; video()?.pause(); },
    next() { advance(1); },
    previous() { advance(-1); },
    skipTarget() { const b = findSkipButton(); if (!b) return null; const r = b.getBoundingClientRect(); return {x:r.x+r.width/2, y:r.y+r.height/2}; },
    listAudioOutputs,
    setAudioOutput(id) { outputDevice = String(id || ''); outputAttempt = ''; if (!video()) { rememberOutput(); post({type:'audio-output',deviceId:outputDevice,ok:true}); } else void applyOutput(true); }
  };
  document.addEventListener('yt-navigate-start', () => { navigatingAt = Date.now(); });
  document.addEventListener('yt-navigate-finish', () => { navigatingAt = 0; if (desiredPlaying) wantsPlay(); });
  const userPlaybackAction = event => {
    if (event.target?.closest?.('input,textarea,[contenteditable="true"]')) return;
    if (event.type === 'pointerdown' && !event.target?.closest?.('.ytp-play-button,video')) return;
    if (event.type === 'keydown' && ![' ', 'k', 'K'].includes(event.key)) return;
    userActionAt = Date.now();
    setTimeout(() => { const v = video(); if (!v || v.ended) return; desiredPlaying = !v.paused; playUntil = 0; if (!desiredPlaying) transition = null; }, 150);
  };
  document.addEventListener('pointerdown', userPlaybackAction, true);
  document.addEventListener('keydown', userPlaybackAction, true);
  navigator.mediaDevices?.addEventListener?.('devicechange', () => { outputAttempt = ''; void listAudioOutputs(); void applyOutput(true); });
  if (document.documentElement && typeof MutationObserver !== 'undefined') {
    let queued = false;
    new MutationObserver(() => { if (!queued) { queued = true; setTimeout(() => { queued = false; try { skipAds(); } catch {} }, 50); } })
      .observe(document.documentElement, {subtree:true, childList:true, attributes:true, attributeFilter:['class','disabled','aria-disabled','style']});
  }
  setInterval(() => {
    try {
      applyMode();
      const p = player(), v = video(), data = p?.getVideoData?.() || {};
      const key = locationKey(), ad = isAd();
      if (key !== epoch) {
        epoch = key; endedAt = 0; transition = null; failedEpoch = ''; outputAttempt = '';
        if (desiredPlaying) wantsPlay();
      }
      syncCaptions();
      skipAds();
      // A playlist-only link must start a track without requiring the full page UI.
      if (location.pathname === '/playlist' && !playlistStarted) {
        // YouTube creates an empty video/player even on its playlist landing page.
        const listId = new URL(location.href).searchParams.get('list');
        const candidates = [...document.querySelectorAll('ytd-playlist-video-renderer a[href*="watch?"], a[href*="watch?"]')];
        const first = candidates.map(a => new URL(a.href, location.origin)).find(url =>
          url.origin === location.origin && url.pathname === '/watch' && /^[\w-]{11}$/.test(url.searchParams.get('v') || '') && url.searchParams.get('list') === listId);
        if (first) { playlistStarted = true; location.replace(first.href); return; }
      }
      if (v !== lastVideo) { lastVideo = v; outputAttempt = ''; setVolume(volume); }
      void applyOutput();
      if (desiredPlaying && v && v.paused && !v.ended && v.readyState >= 2 && Date.now() < playUntil && Date.now() - playAttempt > 600 && Date.now() - userActionAt > 500) {
        playAttempt = Date.now(); v.play().catch(() => {});
      }
      if (v && !v.paused && !ad) playUntil = 0;
      if (ad || !v?.ended || !desiredPlaying) endedAt = 0;
      else if (!endedAt) endedAt = Date.now();
      if (endedAt && Date.now() - endedAt >= 2200 && failedEpoch !== epoch && !transition) advance(1, true);
      stepTransition();
      const error = [...document.querySelectorAll('.ytp-error-content-wrap, ytd-player-error-message-renderer')].find(visible);
      const next = document.querySelector('.ytp-next-button'), previous = document.querySelector('.ytp-prev-button');
      const tracks = playlistTracks(), cc = document.querySelector('.ytp-subtitles-button');
      post({type:'state', url:location.href, videoId:data.video_id || new URL(location.href).searchParams.get('v') || '',
        title:data.title || document.querySelector('h1.ytd-watch-metadata')?.textContent?.trim() || '',
        playing:!!v && !v.paused && !v.ended && v.readyState >= 3, hasVideo:!!v && v.readyState >= 2,
        time:v?.currentTime || 0, duration:Number.isFinite(v?.duration) ? v.duration : 0, volume:v ? Math.round(v.volume * 100) : volume,
        hasNext:!!adjacent(1, tracks) || (!new URL(location.href).searchParams.get('list') && enabled(next)),
        hasPrevious:!!previous && previous.getAttribute('aria-disabled') !== 'true' && getComputedStyle(previous).display !== 'none',
        playlistCount:tracks.length, tracks, adPlaying:ad, skippedAds, transitioning:!!transition,
        captionsRequested:captions, captionsEnabled:cc?.getAttribute('aria-pressed') === 'true',
        captionsAvailable:!!cc && cc.getAttribute('aria-disabled') !== 'true' && getComputedStyle(cc).display !== 'none',
        error:error?.textContent?.trim() || '', needsPage:!p && document.readyState === 'complete'});
    } catch (error) { post({type:'bridge-error',message:String(error)}); }
  }, 400);
})();
