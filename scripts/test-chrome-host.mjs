import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, copyFile, writeFile, readFile, rename } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
await mkdir(path.join(root, 'artifacts/chrome-host'), { recursive: true });
const output = await mkdtemp(path.join(root, 'artifacts/chrome-host/run-'));
const host = path.join(output, 'TurnTabler.ChromeHost.exe');
for (const name of ['TurnTabler.ChromeHost.exe', 'TurnTabler.ChromeHost.exe.config'])
  await copyFile(path.join(root, 'release/chrome-extension/host', name), path.join(output, name));
const origin = 'chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/';
function frame(value) {
  const body = Buffer.from(JSON.stringify(value)), header = Buffer.alloc(4);
  header.writeInt32LE(body.length); return Buffer.concat([header, body]);
}
function request(value, caller = origin, raw, onStart) {
  return new Promise((resolve, reject) => {
    const child = spawn(host, [caller], { windowsHide: true });
    if (onStart) child.once('spawn', () => { void onStart(child.pid).catch(reject); });
    const chunks = [], errors = [];
    const timer = setTimeout(() => { child.kill(); reject(new Error('Host timed out')); }, 15000);
    child.stdout.on('data', data => chunks.push(data));
    child.stderr.on('data', data => errors.push(data));
    child.on('error', reject);
    child.on('close', code => {
      clearTimeout(timer);
      try {
        assert.equal(code, 0, Buffer.concat(errors).toString());
        const bytes = Buffer.concat(chunks);
        assert.equal(bytes.readInt32LE(), bytes.length - 4);
        resolve(JSON.parse(bytes.subarray(4)));
      } catch (error) { reject(error); }
    });
    child.stdin.on('error', () => {});
    child.stdin.end(raw || frame(value));
  });
}
assert.equal((await request({ action: 'getSettings' })).available, false);
const appPath = path.join(root, 'release/single-file/TurnTabler.exe');
const saved = await request({ action: 'setPath', appPath });
assert.ok(saved.ok && saved.available); assert.equal(saved.appVersion, '1.0.0.0');
assert.equal((await request({ action: 'getSettings' })).appPath, appPath);
let pickerClosed;
const cancelled = await request({ action: 'choosePath' }, origin, undefined, appId => {
  pickerClosed = new Promise((resolve, reject) => {
    const script = `Add-Type -AssemblyName UIAutomationClient; Add-Type -AssemblyName UIAutomationTypes;
      $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, ${appId});
      $deadline = [DateTime]::UtcNow.AddSeconds(8);
      while ([DateTime]::UtcNow -lt $deadline) {
        $dialog = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition);
        if ($dialog) { $dialog.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); exit 0 }
        Start-Sleep -Milliseconds 100
      }; exit 1`;
    const closer = spawn('powershell.exe', ['-NoProfile', '-Command', script], { windowsHide: true, stdio: 'ignore' });
    closer.on('error', reject); closer.on('close', code => code === 0 ? resolve() : reject(new Error('Native file picker was not found')));
  });
  return pickerClosed;
});
await pickerClosed;
assert.ok(cancelled.ok && cancelled.cancelled);
assert.equal((await request({ action: 'getSettings' })).appPath, appPath, 'Cancelling file selection preserves the existing path');
for (const requestValue of [null, {}, { action: 'unknown' }, { action: 'setPath', appPath: 'relative/TurnTabler.exe' },
  { action: 'setPath', appPath: 'C:\\missing\\TurnTabler.exe' }, { action: 'setPath', appPath: host },
  { action: 'play', url: 'file:///C:/test' }, { action: 'play', url: 'https://youtube.com.evil.org/watch?v=2qfoSxRRCJc' },
  { action: 'play', url: 'https://user@youtube.com/watch?v=2qfoSxRRCJc' }, { action: 'play', url: 'https://youtube.com/@channel' }]) {
  assert.equal((await request(requestValue)).ok, false, JSON.stringify(requestValue));
}
assert.equal((await request({ action: 'ping' }, 'chrome-extension://not-allowed/')).ok, false);
for (const size of [0, -1, 20000]) {
  const bytes = Buffer.alloc(4); bytes.writeInt32LE(size);
  assert.equal((await request(null, origin, bytes)).ok, false);
}
assert.equal((await request(null, origin, frame({ action: 'ping' }).subarray(0, 9))).ok, false);
assert.equal((await request({ action: 'getSettings' })).appPath, appPath, 'Invalid saves must preserve the current path');
// Paths containing spaces/Korean work, and a moved EXE can be repaired without reinstalling the host.
const relocated = path.join(output, '경로 변경 테스트'); await mkdir(relocated);
const copy = path.join(relocated, 'TurnTabler.exe'); await copyFile(appPath, copy);
assert.equal((await request({ action: 'setPath', appPath: `"${copy}"` })).appPath, copy);
await rename(copy, copy + '.moved');
const missing = await request({ action: 'getSettings' });
assert.ok(missing.ok && !missing.available); assert.equal(missing.appPath, copy);
assert.equal((await request({ action: 'setPath', appPath })).available, true);
assert.equal((await request({ action: 'ping' })).appVersion, '1.0.0.0');
const oldPath = path.join(root, 'release/v2.1.2/TurnTabler.exe');
if (await readFile(oldPath).then(() => true).catch(() => false)) {
  const old = await request({ action: 'setPath', appPath: oldPath });
  assert.ok(old.ok && old.available); assert.equal(old.appVersion, '2.1.2.0');
}
await writeFile(path.join(output, 'result.json'), JSON.stringify({ success: true, appPath, version: saved.appVersion,
  invalidRequestsRejected: true, settingsPersist: true, movedPathRecovery: true, unicodePaths: true }, null, 2));
console.log('PASS: 1.0.0 release validation, native message framing, allowlist, URL rejection, settings persistence, moved EXE recovery.');
console.log(output);
