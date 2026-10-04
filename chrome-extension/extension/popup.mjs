const status = document.querySelector('#status');
const button = document.querySelector('#check');

async function check() {
  button.disabled = true;
  status.textContent = '앱 연결을 확인하는 중…';
  delete status.dataset.ok;
  try {
    const reply = await chrome.runtime.sendNativeMessage('com.turntabler.player', { action: 'ping' });
    if (!reply?.ok || reply.protocol !== 1) throw new Error('호환되는 TurnTabler가 필요합니다.');
    if (reply.available === false) {
      status.dataset.ok = 'false';
      status.textContent = reply.error + ' 아래 설정에서 경로를 변경하세요.';
      return;
    }
    const { lastResult } = await chrome.storage.local.get('lastResult');
    status.dataset.ok = 'true';
    status.textContent = lastResult?.ok === false
      ? `앱이 연결되었습니다. 마지막 요청: ${lastResult.message}`
      : '앱이 연결되었습니다. 유튜브에서 우클릭해 재생해 보세요.';
  } catch {
    status.dataset.ok = 'false';
    status.textContent = '앱 연결이 필요합니다. 설치 ZIP의 Install.cmd를 실행하고 최신 TurnTabler.exe를 선택해 주세요.';
  } finally { button.disabled = false; }
}
button.addEventListener('click', check);
document.querySelector('#settings').addEventListener('click', () => { void chrome.runtime.openOptionsPage(); });
void check();
