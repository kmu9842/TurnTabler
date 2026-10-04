import { spawn } from 'node:child_process';
import { readFile, mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const executable = path.resolve(process.argv[2] || path.join(root, 'release/single-file/TurnTabler.exe'));
const base = path.join(root, 'artifacts/browser');
await mkdir(base, { recursive: true });
const output = await mkdtemp(path.join(base, 'run-'));
const origin = 'chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/';
const env = { ...process.env, TURNTABLER_ARTIFACTS: output };
let widgetPid;

function encode(value) {
  const body = Buffer.from(JSON.stringify(value));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length);
  return Buffer.concat([header, body]);
}
async function host(message, caller = origin) {
  const child = spawn(executable, [caller, '--browser-smoke'], { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  const chunks = [], errors = [];
  child.stdout.on('data', data => chunks.push(data));
  child.stderr.on('data', data => errors.push(data));
  child.stdin.on('error', () => {});
  child.stdin.end(Buffer.isBuffer(message) ? message : encode(message));
  const timer = setTimeout(() => child.kill(), 45000);
  let code;
  try {
    code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
  } finally { clearTimeout(timer); }
  const data = Buffer.concat(chunks);
  assert.ok(data.length >= 4, `Missing framed response (exit ${code}): ${Buffer.concat(errors)}`);
  assert.equal(data.readUInt32LE(0), data.length - 4, 'Native response must contain exactly one binary frame');
  return JSON.parse(data.subarray(4).toString());
}
async function waitFor(name, timeout = 75000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const failure = await readFile(path.join(output, 'browser-failure.json'), 'utf8').catch(() => null);
    if (failure) throw new Error(failure);
    const value = await readFile(path.join(output, name), 'utf8').catch(() => null);
    if (value) return JSON.parse(value);
    await new Promise(resolve => setTimeout(resolve, 350));
  }
  throw new Error(`Timeout waiting for ${name}`);
}

try {
  assert.equal((await host({ action: 'ping' })).ok, true);
  assert.equal((await host({ action: 'play', url: 'https://example.com' })).ok, false);
  assert.equal((await host({ action: 'launch', url: 'calc.exe' })).ok, false);
  assert.equal((await host({ action: 'ping' }, 'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/')).ok, false);
  assert.equal((await host(Buffer.from([255, 255, 255, 127]))).ok, false);
  assert.equal((await host(Buffer.from([20, 0, 0, 0, 123]))).ok, false);
  assert.equal((await host(encode(null))).ok, false);
  console.log('PASS: native framing, origin allowlist, invalid URL/action/size/truncated/null rejection, connection probe');

  const cold = await host({ action: 'play', url: 'https://youtu.be/2qfoSxRRCJc?list=RD2qfoSxRRCJc&index=1' });
  assert.equal(cold.ok, true, JSON.stringify(cold));
  widgetPid = cold.processId;
  console.log(`PASS: app launched and accepted playback (PID ${widgetPid})`);
  const ready = await waitFor('browser-ready.json');
  assert.equal(ready.processId, widgetPid);
  assert.equal(ready.hidden, true);
  const warm = await host({ action: 'play', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43' });
  assert.equal(warm.ok, true, JSON.stringify(warm));
  assert.equal(warm.processId, widgetPid, 'Existing widget must receive playback; no duplicate window');
  const report = await waitFor('browser-verification.json');
  assert.ok(report.success && report.playing && report.hiddenWidgetRestored);
  const result = { ...report, nativeProtocol: true, validatedRequests: true, singleInstance: true, coldResponse: cold, warmResponse: warm };
  await writeFile(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  console.log(`Artifacts: ${output}`);
  await new Promise(resolve => setTimeout(resolve, 1800));
} finally {
  // Only the PID returned by our isolated test instance is eligible for cleanup.
  if (widgetPid) { try { process.kill(widgetPid); } catch {} }
}
