const field = document.querySelector('#app-path');
const status = document.querySelector('#status');
const version = document.querySelector('#version');
const buttons = [...document.querySelectorAll('button')];
async function request(action, extra = {}) {
  buttons.forEach(button => { button.disabled = true; });
  status.textContent = action === 'choosePath' ? '파일 선택 창에서 TurnTabler.exe를 선택하세요.' : '앱 경로를 확인하는 중…';
  delete status.dataset.ok;
  try {
    const reply = await chrome.runtime.sendNativeMessage('com.turntabler.player', { action, ...extra });
    if (!reply?.ok) throw new Error(reply?.error || '경로를 확인하지 못했습니다.');
    if (reply.cancelled) { status.textContent = '파일 선택을 취소했습니다. 기존 경로를 유지합니다.'; return; }
    if (reply.protocol !== 1 || typeof reply.appPath !== 'string') throw new Error('새 ZIP의 Install.cmd를 실행해 연결 프로그램을 업데이트해 주세요.');
    field.value = reply.appPath;
    status.dataset.ok = String(reply.available);
    status.textContent = reply.available
      ? (action === 'getSettings' ? '앱이 연결되었습니다.' : '경로를 저장했습니다. 다음 재생부터 이 EXE를 사용합니다.')
      : reply.error;
    version.textContent = reply.available ? `확인된 앱 버전: ${reply.appVersion}` : '';
  } catch (error) {
    status.dataset.ok = 'false';
    status.textContent = /native messaging host|host not found|communicat/i.test(error.message)
      ? '연결 프로그램을 찾을 수 없습니다. 새 ZIP의 Install.cmd를 실행해 주세요.' : error.message;
  } finally { buttons.forEach(button => { button.disabled = false; }); }
}
document.querySelector('#path-form').addEventListener('submit', event => { event.preventDefault(); void request('setPath', { appPath: field.value }); });
document.querySelector('#browse').addEventListener('click', () => { void request('choosePath'); });
document.querySelector('#check').addEventListener('click', () => { void request('getSettings'); });
void request('getSettings');
