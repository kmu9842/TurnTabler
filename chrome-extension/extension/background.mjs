import { clickedYouTube, normalizeYouTube } from './youtube.mjs';

const host = 'com.turntabler.player';
const menuId = 'play-in-turntabler';

export async function createMenu() {
  await chrome.contextMenus.removeAll();
  chrome.contextMenus.create({
    id: menuId,
    title: 'TurnTabler로 재생',
    contexts: ['page', 'frame', 'link', 'image', 'video', 'audio', 'selection'],
    documentUrlPatterns: ['*://youtube.com/*', '*://*.youtube.com/*', '*://youtu.be/*', '*://www.youtu.be/*']
  }, () => { if (chrome.runtime.lastError) console.error(chrome.runtime.lastError.message); });
}

export function connectionError(error) {
  const message = error?.message || String(error);
  if (/not found|not registered|forbidden|access.*denied/i.test(message)) {
    return '앱 연결이 필요합니다. 별도 설치 ZIP의 Install.cmd를 실행하고 TurnTabler.exe를 선택해 주세요.';
  }
  if (/exited|failed to start|communicating|pipe/i.test(message)) {
    return '확장 설정에서 EXE 경로를 확인해 주세요. 연결 프로그램이 손상되었다면 새 ZIP의 Install.cmd를 다시 실행하세요.';
  }
  return message;
}

export async function playClicked(info, tab) {
  if (info.menuItemId !== menuId) return;
  return requestPlayback(() => clickedYouTube(info, tab));
}

async function requestPlayback(getUrl) {
  try {
    const url = getUrl();
    const reply = await chrome.runtime.sendNativeMessage(host, { action: 'play', url });
    if (!reply?.ok) throw new Error(reply?.error || 'TurnTabler의 응답을 받지 못했습니다.');
    await chrome.storage.local.set({ lastResult: { ok: true, message: 'TurnTabler에 재생 요청을 전달했습니다.' } });
    await chrome.action.setBadgeText({ text: '' });
    await chrome.action.setTitle({ title: 'TurnTabler로 재생' });
    return reply;
  } catch (error) {
    const message = connectionError(error);
    await chrome.storage.local.set({ lastResult: { ok: false, message } });
    await chrome.action.setBadgeBackgroundColor({ color: '#b43a30' });
    await chrome.action.setBadgeText({ text: '!' });
    await chrome.action.setTitle({ title: message });
    try {
      await chrome.notifications.create('turntabler-error', {
        type: 'basic', iconUrl: 'icons/128.png', title: 'TurnTabler', message
      });
    } catch { /* The toolbar badge and popup still show errors when notifications are disabled. */ }
    return { ok: false, error: message };
  }
}

export function receiveYouTubeMessage(message, sender, respond) {
  if (message?.type !== 'turntabler:play') return false;
  // Accept only this extension's content script on a YouTube frame. No page-level
  // postMessage bridge or externally_connectable endpoint can launch the app.
  let trusted = false;
  try {
    const page = new URL(sender.url);
    trusted = sender.id === chrome.runtime.id && Number.isInteger(sender.tab?.id) && page.protocol === 'https:' &&
      ['www.youtube.com', 'youtube.com', 'm.youtube.com', 'music.youtube.com'].includes(page.hostname);
  } catch { }
  if (!trusted) { respond({ ok: false, error: '허용되지 않은 페이지입니다.' }); return false; }
  void requestPlayback(() => normalizeYouTube(message.url)).then(respond, () => respond({ ok: false, error: '재생 요청을 전달하지 못했습니다.' }));
  return true;
}

chrome.runtime.onInstalled.addListener(() => { void createMenu().catch(console.error); });
chrome.runtime.onStartup.addListener(() => { void createMenu().catch(console.error); });
chrome.contextMenus.onClicked.addListener((info, tab) => { void playClicked(info, tab).catch(console.error); });
chrome.runtime.onMessage.addListener(receiveYouTubeMessage);
