(() => {
  const menuSelector = '.ytp-contextmenu';
  const itemClass = 'turntabler-youtube-item';
  const watched = new WeakSet();
  const scheduled = new WeakSet();
  let contextUrl = location.href;
  let sending = false;
  let noticeTimer;

  function videoAddress(target) {
    if (!(target instanceof Element)) return location.href;
    const direct = target.closest('a[href]');
    if (direct) return direct.href;
    // Inline previews on the home/search page belong to a video card, not the page URL.
    const card = target.closest('ytd-rich-item-renderer, ytd-video-renderer, ytd-compact-video-renderer, ytm-video-with-context-renderer');
    const thumbnail = card?.querySelector('a[href*="/watch?"], a[href*="/shorts/"], a[href*="/live/"]');
    return thumbnail?.href || location.href;
  }

  function notice(message, error = false, timeout = 4500) {
    let element = document.getElementById('turntabler-playback-notice');
    if (!element) {
      element = document.createElement('div');
      element.id = 'turntabler-playback-notice';
      element.setAttribute('role', 'status');
      element.setAttribute('aria-live', 'polite');
      // A fullscreen player's descendants remain visible in the fullscreen top layer.
      (document.fullscreenElement || document.body).append(element);
    }
    element.textContent = message;
    element.dataset.error = String(error);
    clearTimeout(noticeTimer);
    if (timeout) noticeTimer = setTimeout(() => element.remove(), timeout);
  }

  async function play(event, menu) {
    if (!event.isTrusted || sending) return;
    event.preventDefault();
    event.stopPropagation();
    sending = true;
    const url = contextUrl;
    // Let YouTube close its own menu so its visibility state stays in sync.
    // Changing display directly makes the next right-click skip YouTube's menu.
    for (const type of ['keydown', 'keyup']) {
      document.dispatchEvent(new KeyboardEvent(type, { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true }));
    }
    notice('TurnTabler로 보내는 중…', false, 0);
    try {
      const reply = await chrome.runtime.sendMessage({ type: 'turntabler:play', url });
      if (!reply?.ok) throw new Error(reply?.error || '재생 요청을 전달하지 못했습니다.');
      notice('TurnTabler에 재생 요청을 전달했습니다.');
    } catch (error) {
      const message = /context invalidated|receiving end|connection/i.test(error.message)
        ? '확장이 업데이트되었습니다. 유튜브 탭을 새로고침해 주세요.' : error.message;
      notice(message, true, 9000);
    } finally { sending = false; }
  }

  function enhance(menu) {
    if (!menu.isConnected) return;
    const items = menu.querySelector('.ytp-panel-menu');
    if (!items) return;
    if (!items.querySelector('.' + itemClass)) {
      const item = document.createElement('div');
      item.className = 'ytp-menuitem ' + itemClass;
      item.setAttribute('role', 'menuitem');
      item.setAttribute('aria-label', 'TurnTabler로 재생');
      item.tabIndex = 0;
      const icon = document.createElement('div');
      icon.className = 'ytp-menuitem-icon';
      const image = document.createElement('img');
      image.src = chrome.runtime.getURL('icons/32.png');
      image.alt = '';
      image.width = image.height = 24;
      icon.append(image);
      const label = document.createElement('div');
      label.className = 'ytp-menuitem-label';
      label.textContent = 'TurnTabler로 재생';
      const content = document.createElement('div');
      content.className = 'ytp-menuitem-content';
      item.append(icon, label, content);
      item.addEventListener('click', event => { void play(event, menu); });
      item.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') void play(event, menu);
        else if (event.key === 'ArrowDown') { event.preventDefault(); item.nextElementSibling?.focus(); }
      });
      items.prepend(item);
    }
    if (!menu.classList.contains('turntabler-youtube-menu')) menu.classList.add('turntabler-youtube-menu');
    // YouTube sets fixed pixel heights before we add our row. CSS frees those
    // heights; keep the expanded menu inside the visible viewport as well.
    const rect = menu.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const dx = Math.max(8 - rect.left, Math.min(0, innerWidth - 8 - rect.right));
    const dy = Math.max(8 - rect.top, Math.min(0, innerHeight - 8 - rect.bottom));
    if (Math.abs(dx) > .5) menu.style.left = (parseFloat(getComputedStyle(menu).left) || 0) + dx + 'px';
    if (Math.abs(dy) > .5) menu.style.top = (parseFloat(getComputedStyle(menu).top) || 0) + dy + 'px';
  }

  function schedule(menu) {
    if (scheduled.has(menu)) return;
    scheduled.add(menu);
    requestAnimationFrame(() => { scheduled.delete(menu); enhance(menu); });
  }

  function watch(menu) {
    if (!watched.has(menu)) {
      watched.add(menu);
      new MutationObserver(() => schedule(menu)).observe(menu, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class']
      });
    }
    schedule(menu);
  }

  function discover(root) {
    if (!(root instanceof Element)) return;
    if (root.matches(menuSelector)) watch(root);
    root.querySelectorAll(menuSelector).forEach(watch);
  }

  document.addEventListener('contextmenu', event => {
    if (!event.isTrusted) return;
    contextUrl = videoAddress(event.target);
    document.querySelectorAll(menuSelector).forEach(watch);
  }, true);
  // Handle lazy menu creation and YouTube's in-page navigation without polling.
  new MutationObserver(records => {
    for (const record of records) for (const node of record.addedNodes) discover(node);
  }).observe(document.documentElement, { childList: true, subtree: true });
  discover(document.documentElement);
})();
