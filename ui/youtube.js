(function (root) {
  function parseYouTube(input) {
    let url;
    try { url = new URL(/^https?:\/\//i.test(input.trim()) ? input.trim() : 'https://' + input.trim()); }
    catch { throw new Error('올바른 유튜브 주소를 입력해 주세요.'); }
    const host = url.hostname.toLowerCase();
    if (!['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be', 'www.youtu.be'].includes(host)) throw new Error('유튜브 링크만 사용할 수 있습니다.');
    const parts = url.pathname.split('/').filter(Boolean);
    const video = host.endsWith('youtu.be') ? parts[0] : url.searchParams.get('v') || (['shorts', 'embed', 'live'].includes(parts[0]) ? parts[1] : null);
    const list = url.searchParams.get('list');
    if (list && !/^[a-zA-Z0-9_-]{10,150}$/.test(list)) throw new Error('재생목록 주소를 확인해 주세요.');
    if (!list && !/^[a-zA-Z0-9_-]{11}$/.test(video || '')) throw new Error('영상 또는 재생목록 주소를 입력해 주세요.');
    const rawTime = url.searchParams.get('t') || url.searchParams.get('start') || '';
    const units = rawTime.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
    const start = /^\d+$/.test(rawTime) ? Number(rawTime) : units ? Number(units[1] || 0) * 3600 + Number(units[2] || 0) * 60 + Number(units[3] || 0) : 0;
    return { video: /^[a-zA-Z0-9_-]{11}$/.test(video || '') ? video : null, list, start, index: Math.max(0, Number.parseInt(url.searchParams.get('index') || '1', 10) - 1) || 0 };
  }
  if (typeof module !== 'undefined') module.exports = { parseYouTube };
  else root.parseYouTube = parseYouTube;
})(typeof window !== 'undefined' ? window : globalThis);
