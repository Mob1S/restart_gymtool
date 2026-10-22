import * as store from './store.js';
const listeners=new Set(), active=new Set(), urls=new Map();
let worker, boot, request=0, generation=0, live=null, video=null, pending=new Map();
let disabled=false, closing=null, lifecycle=0, mediaAbort=new AbortController();
const tasks=new Set(), videos=new Set();
const emit=e=>listeners.forEach(fn=>fn(JSON.stringify(e)));
function releaseVideo(v) {v.pause();v.removeAttribute('src');v.srcObject=null;v.load();videos.delete(v);}
function waitFor(v,event) {
  const signal=mediaAbort.signal;
  return new Promise((resolve,reject)=>{
    const finish=error=>{clearTimeout(timer);v.removeEventListener(event,done);v.removeEventListener('error',failed);signal.removeEventListener('abort',aborted);error?reject(error):resolve();};
    const done=()=>finish(), failed=()=>finish(Error('浏览器无法读取视频')), aborted=()=>finish(Error('已取消'));
    const timer=setTimeout(()=>finish(Error('视频读取超时')),12000);
    v.addEventListener(event,done,{once:true});v.addEventListener('error',failed,{once:true});signal.addEventListener('abort',aborted,{once:true});
    if(signal.aborted)aborted();
  });
}
function rpc(method,args={},transfer=[]) {
  return new Promise((resolve,reject)=>{
    const id=++request;
    const timeout=setTimeout(()=>{ pending.delete(id); reject(Error('视觉引擎超时，请重试')); },90000);
    pending.set(id,{resolve,reject,timeout}); worker.postMessage({id,method,...args},transfer);
  });
}
async function engine() {
  if (!boot) {
    const owned=new Worker(new URL('./worker.js',import.meta.url),{type:'module'});
    worker=owned;
    boot=(async()=>{
    owned.onmessage=({data})=>{
      if(worker!==owned)return;
      if(data.diagnostic){emit({diagnostic:data.diagnostic});return;}
      const task=pending.get(data.id); if (!task) return;
      clearTimeout(task.timeout); pending.delete(data.id);
      data.error ? task.reject(Error(data.error)) : task.resolve(data);
    };
    owned.onerror=e=>{
      if(worker!==owned)return;
      for (const task of pending.values()) {clearTimeout(task.timeout);task.reject(Error(e.message || 'Worker 初始化失败'));}
      pending.clear();owned.terminate();worker=null;boot=null;
    };
    await rpc('init');
  })().catch(e=>{owned.terminate();if(worker===owned){worker=null;boot=null;}throw e;});
  }
  return boot;
}
function invalidate() {
  generation++;
  mediaAbort.abort();mediaAbort=new AbortController();
  // Termination cancels synchronous WASM work promptly as well as pending scheduling.
  worker?.terminate(); worker=null; boot=null;
  for(const task of pending.values()) {clearTimeout(task.timeout);task.reject(Error('已取消'));} pending.clear();
}
function objectUrl(folder,blob) {
  if (!urls.has(folder)) urls.set(folder,URL.createObjectURL(blob));
  return urls.get(folder);
}
async function source(folder) {
  const mine=generation;
  const blob=await store.get(`${folder}/video`);
  if(mine!==generation)throw Error('已取消');
  if (!blob) throw Error('本地视频缺失，可重新导入；训练记录仍然保留');
  active.add(folder);
  const element=document.createElement('video'); element.muted=true; element.playsInline=true;
  videos.add(element);
  if(!element.requestVideoFrameCallback)throw Error('浏览器缺少视频帧时间戳支持，请使用新版 Chrome/Edge');
  element.src=objectUrl(folder,blob); element.preload='auto';
  const loaded=waitFor(element,'loadeddata');element.load();await loaded;
  if (!Number.isFinite(element.duration) || element.duration<=0) {
    // Some MediaRecorder WebM streams lack a duration header.
    const updated=waitFor(element,'timeupdate');element.currentTime=1e10;await updated;
    const reset=waitFor(element,'seeked');element.currentTime=0;await reset;
  }
  return element;
}
function metadata(folder,v) {return {folder,uri:urls.get(folder),duration:Math.round(v.duration*1000),width:v.videoWidth,height:v.videoHeight};}
async function seek(v,t) {
  const target=Math.min(Math.max(0,t/1000),Math.max(0,v.duration-.001));
  if (Math.abs(v.currentTime-target)>.0001) {
    const signal=mediaAbort.signal;
    const presented=new Promise((resolve,reject)=>{
      const aborted=()=>{clearTimeout(timer);v.cancelVideoFrameCallback(id);reject(Error('已取消'));};
      const id=v.requestVideoFrameCallback((_,info)=>{clearTimeout(timer);signal.removeEventListener('abort',aborted);resolve(Math.round(info.mediaTime*1000));});
      const timer=setTimeout(()=>{signal.removeEventListener('abort',aborted);v.cancelVideoFrameCallback(id);reject(Error('浏览器未返回解码帧时间戳'));},12000);
      signal.addEventListener('abort',aborted,{once:true});
      if(signal.aborted)aborted();
    });
    const sought=waitFor(v,'seeked');v.currentTime=target;
    const values=await Promise.all([sought,presented]);v.motionTime=values[1];
  }
  return v.motionTime??0;
}
async function bitmap(v) {
  const factor=Math.min(1,640/Math.max(v.videoWidth,v.videoHeight));
  return createImageBitmap(v,{resizeWidth:Math.max(1,Math.round(v.videoWidth*factor)),resizeHeight:Math.max(1,Math.round(v.videoHeight*factor))});
}
async function jpeg(v) {
  const b=await bitmap(v), canvas=document.createElement('canvas');canvas.width=b.width;canvas.height=b.height;
  canvas.getContext('2d').drawImage(b,0,0);b.close();return canvas.toDataURL('image/jpeg',.85).split(',')[1];
}
function base64(bytes) {
  const data=new Uint8Array(bytes);let out='';
  for(let i=0;i<data.length;i+=8192) out+=String.fromCharCode(...data.subarray(i,i+8192));
  return btoa(out);
}
async function observation(v,t,anchor) {const b=await bitmap(v);return rpc('frame',{bitmap:b,t,anchor},[b]);}
function payload(frames,times,width,height) {return {version:2,algorithm:'lk-fb-template-2',model:'pose-lite-f16-1',coordinateSpace:'upright-normalized',rotationCorrected:true,width,height,frames,times};}
async function analyze(args) {
  const mine=++generation; await engine(); if(mine!==generation) throw Error('已取消');
  await rpc('reset');
  const v=await source(args.folder); video=v;
  if(mine!==generation){releaseVideo(v);throw Error('已取消');}
  const frames=[],times=[],anchors=[...(args.anchors??[])].sort((a,b)=>a.t-b.t); let i=0,w=0,h=0;
  try {
    if(args.start<0 || args.end<=args.start || args.end-args.start>180000) throw Error('请选择不超过 3 分钟的片段');
    // Seeking uses the media timeline, independent of wall time and inference throughput.
    // requestVideoFrameCallback supplies presentation timestamps, not assumed source FPS.
    for(let requested=args.start; requested<args.end; requested+=66) {
      if(mine!==generation) throw Error('已取消');
      const t=await seek(v,requested);
      if(times.length && t<=times.at(-1)) continue;
      let anchor=null; while(i<anchors.length && anchors[i].t<=t+34) anchor=anchors[i++];
      const result=await observation(v,t,anchor);
      result.frame.session=args.session;
      if(mine!==generation) throw Error('已取消');
      frames.push(result.frame);times.push(t);w=result.frame.width;h=result.frame.height;
      emit({session:args.session,folder:args.folder,frame:result.frame,image:base64(result.bytes),progress:Math.min(1,(t-args.start)/(args.end-args.start)),phase:'analyzing'});
    }
    if(frames.length<2) throw Error('片段没有足够可读取的视频帧');
    const name=`result-${crypto.randomUUID()}.json`, data=payload(frames,times,w,h);
    await store.put(`${args.folder}/${name}`,data);
    return {result:name,data};
  } finally {releaseVideo(v);if(video===v)video=null;}
}
async function camera(args) {
  await closeCamera();
  if(!isSecureContext) throw Error('摄像头需要 HTTPS 或本机 localhost，请改用安全地址或导入视频');
  if(!navigator.mediaDevices?.getUserMedia) throw Error('浏览器不支持摄像头，请使用导入视频');
  const mine=++generation; await engine();if(mine!==generation)throw Error('已取消');await rpc('reset');
  let stream;
  try {stream=await navigator.mediaDevices.getUserMedia({audio:false,video:args.deviceId?{deviceId:{exact:args.deviceId},width:{ideal:640}}:{facingMode:{ideal:'environment'},width:{ideal:640}}});}
  catch(e) {throw Error(({NotAllowedError:'摄像头权限被拒绝，请在浏览器设置中允许',NotFoundError:'没有可用摄像头',NotReadableError:'摄像头被占用或无法启动'})[e.name]??e.message);}
  if(mine!==generation){stream.getTracks().forEach(t=>t.stop());throw Error('已取消');}
  const v=document.createElement('video');v.muted=true;v.playsInline=true;v.srcObject=stream;await v.play();
  if(mine!==generation){stream.getTracks().forEach(t=>t.stop());v.srcObject=null;throw Error('已取消');}
  const mime=typeof MediaRecorder==='undefined'?null:['video/webm;codecs=vp9','video/webm;codecs=vp8','video/mp4','video/webm'].find(m=>MediaRecorder.isTypeSupported(m));
  live={mine,session:args.session,v,stream,mime,recording:false,frames:[],times:[],anchor:null,started:performance.now(),closed:false,dropped:0,lastFrame:-1};
  const current=live;
  current.task=(async()=>{
    let lastClock=-1;
    while(live===current && !current.closed) {
      const clock=Math.round(performance.now()-current.started);
      if(current.paused || clock===lastClock || v.currentTime===current.lastFrame) {await new Promise(r=>setTimeout(r,15));continue;}
      lastClock=clock;current.lastFrame=v.currentTime;
      const captured=performance.now();
      const total=v.getVideoPlaybackQuality?.().totalVideoFrames;
      if(Number.isFinite(total)) {
        if(current.lastTotal!=null)current.dropped+=Math.max(0,total-current.lastTotal-1);
        current.lastTotal=total;
      }
      current.inflight=observation(v,clock,current.anchor);
      const result=await current.inflight;current.anchor=null;
      if(live!==current || current.closed || mine!==generation) break;
      const frame={...result.frame,session:args.session,t:current.recording?Math.max(0,clock-current.recordOrigin):clock};
      if(current.recording){current.frames.push(frame);current.times.push(frame.t);}
      const latency=performance.now()-captured;
      const fps=current.lastOutput?1000/Math.max(1,performance.now()-current.lastOutput):1000/Math.max(1,latency);
      current.lastOutput=performance.now();
      emit({session:args.session,frame,image:base64(result.bytes),phase:current.recording?'recording':'preview',duration:current.recording?frame.t:0,
        fps,latencyMs:latency,dropped:current.dropped,canRecord:!!mime});
      if(current.recording && frame.t>=180000) {await stopCamera(false);break;}
    }
  })().catch(e=>{if(live===current) {emit({session:args.session,phase:'failed',error:String(e.message??e)});closeCamera();}});
  return {canRecord:!!mime,devices:(await navigator.mediaDevices.enumerateDevices()).filter(d=>d.kind==='videoinput').map(d=>({id:d.deviceId,label:d.label||'摄像头'}))};
}
async function startCamera() {
  if(!live)throw Error('摄像头尚未准备');
  live.paused=true;await live.inflight;
  live.frames=[];live.times=[];live.recordOrigin=Math.round(performance.now()-live.started);
  if(live.mime) {
    const current=live;current.chunks=[];current.recorder=new MediaRecorder(current.stream,{mimeType:current.mime});
    current.recorder.ondataavailable=e=>{if(e.data.size)current.chunks.push(e.data);};
    current.stopped=new Promise((resolve,reject)=>{current.recorder.onstop=resolve;current.recorder.onerror=e=>reject(e.error??Error('录像失败'));});
    current.recorder.start(1000);
  }
  live.recording=true;live.paused=false;
  return {};
}
async function stopCamera(interrupted=false) {
  const current=live;if(!current)return {};
  const wasRecording=current.recording;current.recording=false;current.closed=true;live=null;
  let recordError=null;
  try {if(current.recorder?.state==='recording') {current.recorder.stop();await current.stopped;}}
  catch(e){recordError=String(e);}
  finally {current.stream.getTracks().forEach(t=>t.stop());current.v.srcObject=null;}
  if(!wasRecording)return {};
  const folder=crypto.randomUUID(),name=`result-${crypto.randomUUID()}.json`;
  active.add(folder);
  const last=current.frames.at(-1),data=payload(current.frames,current.times,last?.width??640,last?.height??360);
  if(current.chunks?.length)await store.put(`${folder}/video`,new Blob(current.chunks,{type:current.mime}));
  await store.put(`${folder}/${name}`,data);
  const result={folder,result:name,data,duration:last?.t??0,status:interrupted||recordError?'interrupted':'stopped',canRecord:!!current.mime&&!!current.chunks?.length};
  if(current.chunks?.length)result.uri=objectUrl(folder,await store.get(`${folder}/video`));
  emit({session:current.session,phase:result.status,completed:result});return result;
}
async function closeCamera() {
  if(!live)return;
  const current=live;live=null;current.closed=true;current.recording=false;
  current.stream.getTracks().forEach(t=>t.stop());current.v.pause();current.v.srcObject=null;
  if(current.recorder?.state==='recording'){current.recorder.stop();await current.stopped;}
  await Promise.allSettled([current.task,current.inflight]);
}
async function closeRuntime(deactivate=false) {
  if(deactivate)disabled=true;
  if(!closing)closing=(async()=>{
    lifecycle++;
    invalidate();await closeCamera();
    for(const v of videos)releaseVideo(v);video=null;
    await Promise.allSettled([...tasks]);
    // Cancellation leaves the editor's unsaved media pinned. Its explicit
    // release operations, or full plugin deactivation, revoke those handles.
    if(disabled){for(const url of urls.values())URL.revokeObjectURL(url);urls.clear();active.clear();}
  })().finally(()=>{closing=null;});
  await closing;
  if(deactivate)listeners.clear();
}
document.addEventListener('visibilitychange',()=>{if(document.hidden&&live){stopCamera(true).catch(e=>emit({phase:'failed',error:String(e)}));}});
window.gymMotion={
  subscribe(fn){listeners.add(fn);return ()=>listeners.delete(fn);},
  async call(method,json) {
    if(method==='activate'){if(closing)await closing;disabled=false;return '{}';}
    if(['close','cancel','deactivate'].includes(method)){await closeRuntime(method==='deactivate');return '{}';}
    if(disabled)throw Error('插件已停用');
    if(closing)throw Error('媒体会话正在关闭');
    const owner=lifecycle;
    const task=this.perform(method,json);
    tasks.add(task);
    try {
      const result=await task;
      if(owner!==lifecycle)throw Error('已取消');
      return result;
    } finally {tasks.delete(task);}
  },
  async perform(method,json) {
    const args=JSON.parse(json);let result={};
    switch(method) {
      case 'capabilities': result={supported:!!window.Worker&&!!window.OffscreenCanvas};break;
      case 'import': {
        const blob=args.bytes?new Blob([Uint8Array.from(atob(args.bytes),c=>c.charCodeAt(0))],{type:args.type??'video/mp4'}):await fetch(args.path).then(r=>r.blob());
        const folder=crypto.randomUUID();await store.put(`${folder}/video`,blob);active.add(folder);
        const v=await source(folder);result=metadata(folder,v);releaseVideo(v);break;
      }
      case 'open': {const v=await source(args.folder);result=metadata(args.folder,v);releaseVideo(v);break;}
      case 'load': result=await store.get(`${args.folder}/${args.result}`);if(!result)throw Error('分析结果缺失，请重新分析');break;
      case 'frame': {const v=await source(args.folder);try {const t=await seek(v,args.t);result={t,image:await jpeg(v),width:v.videoWidth,height:v.videoHeight};}finally{releaseVideo(v);}break;}
      case 'analyze': result=await analyze(args);break;
      case 'cancel': invalidate();video?.pause();await closeCamera();break;
      case 'camera': result=await camera(args);break;
      case 'freezeCamera':if(live){live.paused=true;await live.inflight;}break;
      case 'mark': if(live){await rpc('mark',{anchor:args.anchor});live.paused=false;}break;
      case 'renderOptions':break;
      case 'startCamera':result=await startCamera();break;
      case 'stopCamera':result=await stopCamera(args.interrupted??false);break;
      case 'release': active.delete(args.folder);if(urls.has(args.folder)){URL.revokeObjectURL(urls.get(args.folder));urls.delete(args.folder);}break;
      case 'collect':await store.collect(args.keep,active,args.results);break;
      case 'close':invalidate();await closeCamera();break;
      default:throw Error(`未知媒体操作 ${method}`);
    }
    return JSON.stringify(result??{});
  },
};
