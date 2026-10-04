(() => {
  if (window !== window.top || location.hostname !== 'www.youtube.com') return;
  const style = document.createElement('style');
  style.id = 'turntabler-widget-style';
  style.textContent = `
    html.tt-widget,html.tt-widget body{margin:0!important;overflow:hidden!important;background:#111!important}
    html.tt-widget body *{visibility:hidden!important}
    html.tt-widget #movie_player,html.tt-widget #movie_player *{visibility:visible!important}
    html.tt-widget #movie_player{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;min-width:0!important;min-height:0!important;z-index:2147483000!important;margin:0!important;border-radius:0!important}
    html.tt-widget .html5-video-container{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;transform:none!important}
    html.tt-widget video.html5-main-video{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;object-fit:cover!important;object-position:50% 50%!important;transform:none!important;margin:0!important}
    html.tt-widget .ytp-chrome-top,html.tt-widget .ytp-chrome-bottom,html.tt-widget .ytp-gradient-top,html.tt-widget .ytp-gradient-bottom{visibility:hidden!important;display:none!important}
    html.tt-widget:not(.tt-captions) .ytp-caption-window-container{visibility:hidden!important;display:none!important}
  `;
  let widget = true, volume = Number(window.__turntablerInitialVolume ?? 65);
  let autoplay = true, attempted = 0, lastVideo;
  let captions = !!window.__turntablerInitialCaptions, captionAttempt = 0, playlistStarted = false;
  const player = () => document.getElementById('movie_player');
  const video = () => document.querySelector('video.html5-main-video') || document.querySelector('video');
  const visible = element => element && getComputedStyle(element).display !== 'none' && element.getClientRects().length;
  const post = state => window.chrome?.webview?.postMessage(state);
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
  window.turntablerNative = {
    setWidgetMode(value) { widget = !!value; applyMode(); },
    setVolume,
    setCaptions(value) { captions = !!value; captionAttempt = 0; applyMode(); syncCaptions(); },
    toggle() { autoplay = false; const v = video(); if (v) { if (v.paused) v.play().catch(() => post({type:'notice', message:'유튜브 페이지에서 재생을 눌러 주세요.'})); else v.pause(); } },
    play() { autoplay = true; attempted = 0; const v = video(); if (v) v.play().catch(() => {}); },
    pause() { autoplay = false; video()?.pause(); },
    next() { autoplay = true; attempted = 0; const p = player(); if (p?.nextVideo) p.nextVideo(); else document.querySelector('.ytp-next-button')?.click(); },
    previous() { autoplay = true; attempted = 0; const p = player(); if (p?.previousVideo) p.previousVideo(); else document.querySelector('.ytp-prev-button')?.click(); }
  };
  setInterval(() => {
    try {
      applyMode();
      const p = player(), v = video(), data = p?.getVideoData?.() || {};
      syncCaptions();
      // A playlist-only link must start a track without requiring the full page UI.
      if (location.pathname === '/playlist' && !playlistStarted) {
        // YouTube creates an empty video/player even on its playlist landing page.
        const listId = new URL(location.href).searchParams.get('list');
        const candidates = [...document.querySelectorAll('ytd-playlist-video-renderer a[href*="watch?"], a[href*="watch?"]')];
        const first = candidates.map(a => new URL(a.href, location.origin)).find(url =>
          url.origin === location.origin && url.pathname === '/watch' && /^[\w-]{11}$/.test(url.searchParams.get('v') || '') && url.searchParams.get('list') === listId);
        if (first) { playlistStarted = true; location.replace(first.href); return; }
      }
      if (v !== lastVideo) { lastVideo = v; setVolume(volume); }
      if (autoplay && v && v.paused && v.readyState >= 2 && attempted++ < 25) v.play().catch(() => {});
      if (v && !v.paused) autoplay = false;
      const error = [...document.querySelectorAll('.ytp-error-content-wrap, ytd-player-error-message-renderer')].find(visible);
      const next = document.querySelector('.ytp-next-button'), previous = document.querySelector('.ytp-prev-button');
      const tracks = playlistTracks(), cc = document.querySelector('.ytp-subtitles-button');
      post({type:'state', url:location.href, videoId:data.video_id || new URL(location.href).searchParams.get('v') || '',
        title:data.title || document.querySelector('h1.ytd-watch-metadata')?.textContent?.trim() || '',
        playing:!!v && !v.paused && !v.ended && v.readyState >= 3, hasVideo:!!v && v.readyState >= 2,
        time:v?.currentTime || 0, duration:Number.isFinite(v?.duration) ? v.duration : 0, volume:v ? Math.round(v.volume * 100) : volume,
        hasNext:!!next && next.getAttribute('aria-disabled') !== 'true' && (tracks.length > 1 || !!next.getAttribute('href')),
        hasPrevious:!!previous && previous.getAttribute('aria-disabled') !== 'true' && getComputedStyle(previous).display !== 'none',
        playlistCount:tracks.length, tracks,
        captionsRequested:captions, captionsEnabled:cc?.getAttribute('aria-pressed') === 'true',
        captionsAvailable:!!cc && cc.getAttribute('aria-disabled') !== 'true' && getComputedStyle(cc).display !== 'none',
        error:error?.textContent?.trim() || '', needsPage:!p && document.readyState === 'complete'});
    } catch (error) { post({type:'bridge-error',message:String(error)}); }
  }, 400);
})();
