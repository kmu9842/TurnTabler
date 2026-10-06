import {spawn,execFileSync} from 'node:child_process';
import {mkdirSync,readFileSync,writeFileSync,statSync} from 'node:fs';
import {resolve,join} from 'node:path';
import assert from 'node:assert/strict';
import {connectOBS} from './obs-client.mjs';

const output=resolve('artifacts/obs',new Date().toISOString().replace(/[:.]/g,'-'));
mkdirSync(output,{recursive:true});
const app=spawn(resolve(process.argv[2] || 'artifacts/windows-dev/TurnTabler.exe'),['--obs-smoke'],{windowsHide:true,stdio:'ignore',env:{...process.env,TURNTABLER_ARTIFACTS:output}});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const obs=await connectOBS();
let recording=false;
const source='TurnTabler Audio',scene='TurnTabler';
const peaks={tone:[],silence:[],resumed:[]};
let phase='',phaseAt=Date.now();
try {
  for(let i=0;i<80;i++) {
    try {if(JSON.parse(readFileSync(join(output,'player-state.json'),'utf8')).phase==='ready')break;}catch{}
    if(i===79)throw new Error('Audio fixture did not become ready');
    await delay(500);
  }
  const inputs=await obs.request('GetInputList');
  assert.ok(inputs.inputs.every(i=>i.inputName===source),'Use the dedicated TurnTabler scene collection without other capture sources');
  if(inputs.inputs[0]?.inputKind!=='ffmpeg_source') {
    if(inputs.inputs.length) { await obs.request('RemoveInput',{inputName:source}); await delay(800); }
    await obs.request('CreateInput',{sceneName:scene,inputName:source,inputKind:'ffmpeg_source',inputSettings:{is_local_file:false,input:''},sceneItemEnabled:true});
  }
  const endpoint=JSON.parse(readFileSync(join(output,'endpoint.json'),'utf8')).url;
  await obs.request('SetInputSettings',{inputName:source,inputSettings:{is_local_file:false,input:endpoint,input_format:'wav',ffmpeg_options:'ignore_length=1 analyzeduration=0 probesize=4096',restart_on_activate:true,close_when_inactive:false,buffering_mb:1,reconnect_delay_sec:1},overlay:true});
  await obs.request('SetInputMute',{inputName:source,inputMuted:false});
  await obs.request('SetInputAudioMonitorType',{inputName:source,monitorType:'OBS_MONITORING_TYPE_NONE'});
  await obs.request('SetCurrentProgramScene',{sceneName:scene});
  await obs.request('SetVideoSettings',{baseWidth:640,baseHeight:360,outputWidth:640,outputHeight:360,fpsNumerator:30,fpsDenominator:1});
  await obs.request('SetRecordDirectory',{recordDirectory:output});
  await delay(2500);
  obs.onEvent(e=>{
    if(e.eventType!=='InputVolumeMeters'||!peaks[phase]||Date.now()-phaseAt<1800)return;
    const input=e.eventData.inputs.find(i=>i.inputName===source);
    if(input)peaks[phase].push(Math.max(0,...input.inputLevelsMul.flat()));
  });
  await obs.request('StartRecord');recording=true;
  writeFileSync(join(output,'start-audio'),'ready');
  for(let i=0;i<100;i++) {
    const state=JSON.parse(readFileSync(join(output,'player-state.json'),'utf8'));
    if(phase!==state.phase){phase=state.phase;phaseAt=Date.now();console.log('Audio phase:',phase);}
    if(phase==='error')throw new Error(state.error);
    if(phase==='complete')break;
    if(i===99)throw new Error('Audio test timeout');
    await delay(400);
  }
  const record=await obs.request('StopRecord');recording=false;
  await delay(1500); // OBS acknowledges stopping before the muxer has fully flushed.
  const measurements=Object.fromEntries(Object.entries(peaks).map(([key,values])=>[key,{samples:values.length,peak:Math.max(0,...values)}]));
  const ffmpeg=process.env.FFMPEG || execFileSync('python',['-c','import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())'],{encoding:'utf8',windowsHide:true}).trim();
  const decoded=execFileSync(ffmpeg,['-v','error','-i',record.outputPath,'-vn','-f','f32le','-ac','1','-ar','48000','pipe:1'],{maxBuffer:32*1024*1024,windowsHide:true});
  const rms=(start,end)=>{let sum=0,count=0;for(let i=start*48000*4;i<Math.min(decoded.length,end*48000*4);i+=4){sum+=decoded.readFloatLE(i)**2;count++;}return Math.sqrt(sum/Math.max(1,count));};
  const audio={tone:rms(4,8),silence:rms(13,15),resumed:rms(20,24)};
  const result={success:audio.tone>0.001&&audio.resumed>0.001&&audio.silence<0.0001,sourceKind:'ffmpeg_source',scope:'TurnTabler WebView2 process only; default speakers unchanged',audio,measurements,recording:record.outputPath,bytes:statSync(record.outputPath).size};
  writeFileSync(join(output,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
  assert.ok(result.success,'OBS must capture both tone periods and silence during pause');
} finally {
  if(recording)await obs.request('StopRecord').catch(()=>{});
  obs.close();
  if(app.exitCode===null){await delay(3500);if(app.exitCode===null)app.kill();}
}
