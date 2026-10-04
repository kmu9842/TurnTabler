const $ = id => document.getElementById(id);
let player, ready = false, pending, trackSignature = '', paletteBusy = false, ambientLayer = 0;
const status = (message, error = false) => { $('status').textContent = message; $('status').hidden = !error; };
const defaults = { pin: true, effect: true, ambient: true, rotation: true, volume: 65, strength: 70, size: '1', corner: 'bottom-right' };
let settings;
const preferences = window.desktop?.preferences() || {};
try { settings = { ...defaults, ...(preferences.settings || JSON.parse(localStorage.getItem('turntabler-settings') || '{}')) }; } catch { settings = { ...defaults }; }
function save() { localStorage.setItem('turntabler-settings', JSON.stringify(settings)); window.desktop?.savePreferences({ settings, url: $('url').value.trim() }); }
function applySettings() {
  for (const key of ['pin', 'effect', 'ambient', 'rotation']) $(key).checked = settings[key];
  $('volume').value = settings.volume; $('deck-volume').value = settings.volume; document.documentElement.style.setProperty('--volume', settings.volume/100); $('light-strength').value = settings.strength; $('size').value = settings.size; $('corner').value = settings.corner;
  document.body.classList.toggle('no-effect', !settings.effect); document.body.classList.toggle('no-ambient', !settings.ambient); document.body.classList.toggle('no-rotation', !settings.rotation);
  document.documentElement.style.setProperty('--light-strength', settings.strength / 100);
  if (ready) player.setVolume(Number(settings.volume));
}
function load(source) {
  if (!ready) { pending = source; return; }
  trackSignature = ''; $('tracks').replaceChildren();
  if (source.list) player.loadPlaylist({ list: source.list, listType: 'playlist', index: source.index, startSeconds: source.start });
  else player.loadVideoById({ videoId: source.video, startSeconds: source.start });
  document.body.classList.add('loaded'); $('playlist').hidden = !source.list;
  localStorage.setItem('turntabler-url', $('url').value.trim()); status('');
  save();
}
window.onYouTubeIframeAPIReady = () => {
  player = new YT.Player('player', { width: 326, height: 184,
    playerVars: { origin: location.origin, playsinline: 1, controls: 0, rel: 0, fs: 0, cc_load_policy: 0, disablekb: 1, iv_load_policy: 3 },
    events: {
      onReady: () => { ready = true; applySettings(); if (pending) { load(pending); pending = null; } },
      onStateChange: event => { document.body.classList.toggle('playing', event.data === YT.PlayerState.PLAYING); $('video-hit').setAttribute('aria-label', event.data === YT.PlayerState.PLAYING ? '일시정지' : '재생'); update(); },
      onAutoplayBlocked: () => status('원판을 클릭해 재생하세요.', true),
      onError: event => { document.body.classList.remove('playing'); const messages = { 2: '영상 주소를 확인하세요.', 5: '영상 재생에 실패했습니다.', 100: '삭제되었거나 비공개인 영상입니다.', 101: '외부 재생을 허용하지 않는 영상입니다.', 150: '외부 재생을 허용하지 않는 영상입니다.', 153: '유튜브 연결을 확인하세요.' }; status(messages[event.data] || '영상 또는 재생목록을 재생할 수 없습니다.', true); }
    }
  });
};
function update() {
  if (!ready) return;
  const data = player.getVideoData(); $('video-hit').title = data.title || '';
  const list = player.getPlaylist() || [], index = player.getPlaylistIndex();
  $('previous').disabled = !list.length; $('next').disabled = !list.length;
  if (!$('playlist').hidden && list.length) {
    const signature = list.join(',');
    if (signature !== trackSignature) { trackSignature = signature; $('tracks').replaceChildren(); list.forEach((id, i) => { const option = document.createElement('option'); option.value = i; option.textContent = String(i + 1); $('tracks').append(option); }); }
    if (index >= 0 && $('tracks').options[index]) { $('tracks').options[index].textContent = (index + 1) + '. ' + (data.title || ''); $('tracks').value = index; }
  }
}
async function reflectVideo() {
  if (!ready || paletteBusy || player.getPlayerState() !== YT.PlayerState.PLAYING || !window.desktop) return;
  paletteBusy = true;
  try {
    const rect = document.querySelector('.projection').getBoundingClientRect();
    const frame = await window.desktop.frame({ x: Math.round(rect.x + rect.width * .1), y: Math.round(rect.y + rect.height * .1), width: Math.round(rect.width * .8), height: Math.round(rect.height * .8) });
    if (!frame) return;
    const image = new Image(); image.src = frame.image; await image.decode();
    const canvases = document.querySelectorAll('.ambient-canvas');
    const canvas = canvases[ambientLayer];
    canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
    canvas.style.opacity = '1'; canvases[1-ambientLayer].style.opacity = '0'; ambientLayer = 1-ambientLayer;
    document.querySelector('.video-wash').style.backgroundImage = `url("${frame.image}")`;
    const diameter = document.querySelector('.projection').clientWidth + 2;
    const videoWidth = Math.ceil(Math.max(diameter,diameter*frame.aspect)), videoHeight = Math.ceil(Math.max(diameter,diameter/frame.aspect));
    if ($('player').style.width !== videoWidth+'px' || $('player').style.height !== videoHeight+'px') player.setSize(videoWidth,videoHeight);
    $('player').style.clipPath = 'none';
  } catch {} finally { paletteBusy = false; }
}
$('link-form').addEventListener('submit', event => { event.preventDefault(); try { load(parseYouTube($('url').value)); } catch (error) { status(error.message, true); } });
$('video-hit').onclick = () => { if (!ready) return; if (!player.getVideoData().video_id) return $('link-form').requestSubmit(); player.getPlayerState() === YT.PlayerState.PLAYING ? player.pauseVideo() : player.playVideo(); };
$('previous').onclick = () => ready && player.previousVideo(); $('next').onclick = () => ready && player.nextVideo();
$('tracks').onchange = () => ready && player.playVideoAt(Number($('tracks').value));
function showSettings(show) { $('settings').hidden = !show; $('settings-toggle').setAttribute('aria-expanded', String(show)); }
$('settings-toggle').onclick = () => showSettings($('settings').hidden); $('settings-close').onclick = () => showSettings(false);
document.addEventListener('keydown', event => { if (event.key === 'Escape') showSettings(false); });
document.addEventListener('pointerdown', event => { if (!event.target.closest('#settings, #settings-toggle')) showSettings(false); });
for (const key of ['effect','ambient','rotation']) $(key).onchange = () => { settings[key] = $(key).checked; save(); applySettings(); };
$('pin').onchange = () => { settings.pin = $('pin').checked; save(); window.desktop?.pin(settings.pin); };
function changeVolume(event) { settings.volume = Number(event.target.value); $('volume').value = settings.volume; $('deck-volume').value = settings.volume; document.documentElement.style.setProperty('--volume',settings.volume/100); save(); if (ready) { player.unMute(); player.setVolume(settings.volume); } }
$('volume').oninput = changeVolume; $('deck-volume').oninput = changeVolume;
$('light-strength').oninput = () => { settings.strength = Number($('light-strength').value); save(); applySettings(); };
$('size').onchange = () => { settings.size = $('size').value; save(); window.desktop?.resize(Number(settings.size)); };
$('corner').onchange = () => { settings.corner = $('corner').value; save(); window.desktop?.corner(settings.corner); };
$('close').onclick = () => window.desktop?.close(); $('minimize').onclick = () => window.desktop?.minimize();
$('url').value = preferences.url || localStorage.getItem('turntabler-url') || ''; $('previous').disabled = true; $('next').disabled = true;
applySettings(); window.desktop?.pin(settings.pin); window.desktop?.resize(Number(settings.size)); window.desktop?.corner(settings.corner);
const script = document.createElement('script'); script.src = 'https://www.youtube.com/iframe_api'; script.onerror = () => status('유튜브 연결에 실패했습니다.', true); document.head.append(script);
setTimeout(() => { if (!ready) status('인터넷 연결을 확인하세요.', true); }, 15000);
setInterval(update, 800); setInterval(reflectVideo, 220);
