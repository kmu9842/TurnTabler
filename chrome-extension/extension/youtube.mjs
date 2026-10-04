const hosts = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be', 'www.youtu.be']);

export function normalizeYouTube(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('영상 또는 재생목록에서 우클릭해 주세요.'); }
  if (!['https:', 'http:'].includes(url.protocol) || !hosts.has(url.hostname) || url.username || url.password) {
    throw new Error('유튜브 영상 또는 재생목록만 재생할 수 있습니다.');
  }
  const segments = url.pathname.split('/').filter(Boolean);
  let video = url.searchParams.get('v');
  if (url.hostname.endsWith('youtu.be')) video = segments[0] ?? null;
  else if (['shorts', 'live', 'embed'].includes(segments[0])) video = segments[1] ?? null;
  const list = url.searchParams.get('list');
  if (video !== null && !/^[a-zA-Z0-9_-]{11}$/.test(video)) throw new Error('영상 주소를 확인해 주세요.');
  if (list !== null && !/^[a-zA-Z0-9_-]{10,150}$/.test(list)) throw new Error('재생목록 주소를 확인해 주세요.');
  if (video === null && list === null) throw new Error('영상 또는 재생목록에서 우클릭해 주세요.');
  const query = new URLSearchParams();
  if (video !== null) query.set('v', video);
  if (list !== null) query.set('list', list);
  const index = url.searchParams.get('index');
  if (index && /^\d+$/.test(index) && Number(index) > 0 && Number(index) <= 2147483647) query.set('index', String(Number(index)));
  const time = url.searchParams.get('t') ?? url.searchParams.get('start');
  if (time && /^(?:\d+|(?:\d+h)?(?:\d+m)?(?:\d+s)?)$/.test(time)) query.set('t', time);
  return `https://www.youtube.com/${video === null ? 'playlist' : 'watch'}?${query}`;
}

export function clickedYouTube(info, tab) {
  // A clicked thumbnail/link takes precedence over the currently playing page.
  // Never silently play the current video when a different, invalid link was clicked.
  return normalizeYouTube(info.linkUrl || info.frameUrl || info.pageUrl || tab?.url);
}
