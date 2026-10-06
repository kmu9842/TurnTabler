import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../native/YouTubeBridge.js', import.meta.url), 'utf8');
const ids = ['2qfoSxRRCJc', 'dQw4w9WgXcQ', 'aaaaaaaaaaa'];
function fixture(options = {}) {
  let now = 100000, interval;
  const timers = [], events = new Map(), messages = [], storage = options.storage || new Map();
  const count = {skip:0, next:0, nextClick:0, play:0, navigations:[]};
  const state = {ad:false, skipVisible:false, skipEnabled:true, nativeNext:false, buttonNext:false, index:0, devices:[{kind:'audiooutput',deviceId:'default',label:'Default'},{kind:'audiooutput',deviceId:'speaker-1',label:'USB Speaker'}]};
  let current = new URL(`https://www.youtube.com/watch?v=${ids[0]}&list=RD2qfoSxRRCJc&index=1&t=40`);
  const location = {
    get hostname(){return current.hostname}, get origin(){return current.origin}, get pathname(){return current.pathname},
    get href(){return current.href}, set href(value){current=new URL(value)},
    assign(value){count.navigations.push(value);if(!options.blockNavigation){current=new URL(value);state.index=Number(current.searchParams.get('index'))-1}},
    replace(value){this.assign(value)}
  };
  const video = {paused:false, ended:false, readyState:4, currentTime:10, duration:120, volume:.65, muted:false, sinkId:'',
    play(){count.play++;this.paused=false;return Promise.resolve()}, pause(){this.paused=true},
    async setSinkId(id){if(id && !state.devices.some(d=>d.deviceId===id)){const e=new Error('missing');e.name='NotFoundError';throw e}this.sinkId=id}
  };
  const skip = {isConnected:true, get disabled(){return !state.skipEnabled},getAttribute(){return null},getClientRects(){return state.skipVisible?[{}]:[]},getBoundingClientRect(){return {x:100,y:100,width:50,height:30}},click(){count.skip++}};
  const advance = () => {if(state.index<ids.length-1){state.index++;location.href=`https://www.youtube.com/watch?v=${ids[state.index]}&list=RD2qfoSxRRCJc&index=${state.index+1}`;video.ended=false;video.paused=true;video.currentTime=0}};
  const next = {isConnected:true,getAttribute(){return null},click(){count.nextClick++;if(state.buttonNext)advance()}};
  const tracks = (options.ids || ids).map((id,index)=>({querySelector(selector){
    if(selector.startsWith('a'))return {href:`https://www.youtube.com/watch?v=${id}&list=RD2qfoSxRRCJc&index=${index+1}&t=99`,title:id};
    return {textContent:String(index+1)}
  },hasAttribute(){return state.index===index}}));
  const player = {classList:{contains(name){return name==='ad-showing'&&state.ad}},getVideoData(){return {video_id:current.searchParams.get('v'),title:'Fixture'}},setVolume(){},unMute(){},mute(){},
    nextVideo(){count.next++;if(state.nativeNext)advance()},previousVideo(){},
    querySelectorAll(selector){return selector.startsWith('.ytp-ad')?[skip]:[]}
  };
  const document = {readyState:'complete',createElement(){return {isConnected:false}},documentElement:{append(el){el.isConnected=true},classList:{toggle(){}}},
    getElementById(){return player},querySelector(selector){if(selector.startsWith('video'))return video;if(selector==='.ytp-next-button')return next;return null},
    querySelectorAll(selector){return selector==='ytd-playlist-panel-video-renderer'?tracks:[]},
    addEventListener(name,fn){events.set(name,fn)}
  };
  const window = {chrome:{webview:{postMessage(message){messages.push(message)}}}};window.top=window;
  const mediaEvents=new Map();
  vm.runInNewContext(source,{window,document,location,URL,Date:class{static now(){return now}},
    navigator:{mediaDevices:{enumerateDevices:async()=>state.devices,addEventListener(name,fn){mediaEvents.set(name,fn)}}},
    localStorage:{getItem:key=>storage.has(key)?storage.get(key):null,setItem:(key,value)=>storage.set(key,value)},
    getComputedStyle(){return {display:'block',visibility:'visible'}},
    setInterval(fn){interval=fn},setTimeout(fn,ms){timers.push({fn,at:now+ms})}
  });
  function tick(ms=400){now+=ms;const due=timers.filter(t=>t.at<=now);for(const item of due){timers.splice(timers.indexOf(item),1);item.fn()}interval()}
  return {state,count,video,location,messages,storage,events,mediaEvents,api:window.turntablerNative,tick,
    end(){video.ended=true;video.paused=true;video.currentTime=video.duration},advance,
    noErrors(){assert.deepEqual(messages.filter(m=>m.type==='bridge-error'),[])}};
}

test('skips enabled visible ads, retries, then requests native input once',()=>{
  const f=fixture();f.state.ad=true;f.state.skipVisible=true;f.tick();assert.equal(f.count.skip,1);
  for(let i=0;i<15;i++)f.tick();assert.equal(f.count.skip,4);assert.equal(f.messages.filter(m=>m.type==='skip-input').length,1);
  f.state.ad=false;f.tick();assert.equal(f.count.skip,4);f.noErrors();
});
test('never clicks hidden/disabled skip controls or ordinary content',()=>{
  const f=fixture();f.state.ad=true;f.tick();assert.equal(f.count.skip,0);
  f.state.skipVisible=true;f.state.skipEnabled=false;f.tick();assert.equal(f.count.skip,0);
  f.state.skipEnabled=true;f.state.ad=false;f.tick();assert.equal(f.count.skip,0);f.noErrors();
});
test('ad end cannot advance the content playlist',()=>{
  const f=fixture();f.state.ad=true;f.end();for(let i=0;i<30;i++)f.tick();assert.equal(f.count.next,0);f.noErrors();
});
test('native automatic navigation wins without a second next',()=>{
  const f=fixture();f.tick();f.end();f.tick();f.advance();for(let i=0;i<20;i++)f.tick();assert.equal(f.count.next,0);assert.equal(f.count.nextClick,0);f.noErrors();
});
test('ended list falls back from ineffective API to button to verified URL',()=>{
  const f=fixture();f.tick();f.end();for(let i=0;i<22;i++)f.tick();
  assert.equal(f.count.next,1);assert.equal(f.count.nextClick,1);assert.equal(f.count.navigations.length,1);
  const target=new URL(f.count.navigations[0]);assert.equal(target.searchParams.get('v'),ids[1]);assert.equal(target.searchParams.get('list'),'RD2qfoSxRRCJc');assert.equal(target.searchParams.get('index'),'2');assert.equal(target.searchParams.has('t'),false);f.noErrors();
});
test('effective internal next does not also click or navigate',()=>{
  const f=fixture();f.tick();f.state.nativeNext=true;f.api.next();for(let i=0;i<20;i++)f.tick();
  assert.equal(f.count.next,1);assert.equal(f.count.nextClick,0);assert.equal(f.count.navigations.length,0);f.noErrors();
});
test('repeated next requests are coalesced until a transition completes',()=>{
  const f=fixture();f.tick();f.api.next();f.api.next();f.api.next();assert.equal(f.count.next,1);f.noErrors();
});
test('last playlist item does not fall through to an unrelated recommendation',()=>{
  const f=fixture();f.state.index=2;f.location.href=`https://www.youtube.com/watch?v=${ids[2]}&list=RD2qfoSxRRCJc&index=3`;f.tick();f.end();for(let i=0;i<30;i++)f.tick();assert.equal(f.count.next,0);f.noErrors();
});
test('standalone video is not automatically advanced',()=>{
  const f=fixture();f.location.href=`https://www.youtube.com/watch?v=${ids[0]}`;f.tick();f.end();for(let i=0;i<30;i++)f.tick();assert.equal(f.count.next,0);f.noErrors();
});
test('explicit pause survives SPA navigation',()=>{
  const f=fixture();f.tick();f.api.pause();f.advance();for(let i=0;i<15;i++)f.tick();assert.equal(f.count.play,0);assert.equal(f.video.paused,true);f.noErrors();
});
test('playing intent resumes a reused video element after SPA navigation',()=>{
  const f=fixture();f.tick();f.advance();for(let i=0;i<3;i++)f.tick();assert.equal(f.count.play,1);assert.equal(f.video.paused,false);f.noErrors();
});
test('duplicate videos in a playlist advance by occurrence index',()=>{
  const f=fixture({ids:[ids[0],ids[0],ids[2]]});f.tick();f.end();for(let i=0;i<22;i++)f.tick();
  assert.equal(f.count.navigations.length,1);assert.equal(new URL(f.count.navigations[0]).searchParams.get('v'),ids[0]);assert.equal(new URL(f.count.navigations[0]).searchParams.get('index'),'2');f.noErrors();
});
test('failed navigation stops retrying the same ended track',()=>{
  const f=fixture({blockNavigation:true});f.tick();f.end();for(let i=0;i<100;i++)f.tick();
  assert.equal(f.count.next,1);assert.equal(f.count.nextClick,1);assert.equal(f.count.navigations.length,1);assert.ok(f.messages.some(m=>m.type==='notice'));f.noErrors();
});
test('selected speaker persists and unplugging it falls back to default',async()=>{
  const f=fixture();f.tick();f.api.setAudioOutput('speaker-1');await new Promise(setImmediate);
  assert.equal(f.video.sinkId,'speaker-1');assert.equal(f.storage.get('turntabler.outputDevice'),'speaker-1');
  const next=fixture({storage:f.storage});next.tick();await new Promise(setImmediate);assert.equal(next.video.sinkId,'speaker-1');
  f.state.devices=f.state.devices.filter(d=>d.deviceId!=='speaker-1');await f.api.listAudioOutputs();await new Promise(setImmediate);
  assert.equal(f.video.sinkId,'');assert.ok(f.messages.some(m=>m.type==='audio-output'&&m.fallback));f.noErrors();next.noErrors();
});

test('rapid speaker changes cannot persist a stale asynchronous result',async()=>{
  const f=fixture();f.tick();
  let finish;
  f.video.setSinkId=id=>new Promise(resolve=>{finish=()=>{f.video.sinkId=id;resolve()}});
  f.api.setAudioOutput('speaker-1');f.api.setAudioOutput('');
  finish();await new Promise(setImmediate);
  assert.equal(f.messages.some(m=>m.type==='audio-output'&&m.deviceId==='speaker-1'),false);
  finish();await new Promise(setImmediate);
  assert.equal(f.video.sinkId,'');assert.equal(f.storage.get('turntabler.outputDevice'),'');f.noErrors();
});
