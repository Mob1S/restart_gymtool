import {BarTracker} from './tracker.js';
// MediaPipe's pinned loader falls back to self.import in a module Worker.
// Evaluate its local Emscripten loader here, retaining the factory on worker scope.
self.import = async url => {
  const response=await fetch(url);
  if(!response.ok)throw Error('WASM 运行库读取失败');
  new Function(`${await response.text()}; self.ModuleFactory = ModuleFactory;`).call(self);
};
let pose, cv, tracker, last=-1, segment=0, anchored=false, dimensions='', lastGray, poseInitError=null;
async function initialize() {
  self.postMessage({diagnostic:'worker-start'});
  if (!self.OffscreenCanvas) throw Error('浏览器缺少 Worker 图像支持，请使用新版 Chrome/Edge');
  try {
  const {FilesetResolver, PoseLandmarker} = await import('./vendor/vision_bundle.mjs');
  self.postMessage({diagnostic:'pose-module'});
  // CPU/WASM in Worker is the supported path; never fall back to UI-thread inference.
  pose = await PoseLandmarker.createFromOptions(await FilesetResolver.forVisionTasks(new URL('./vendor/wasm', import.meta.url).href), {
    baseOptions:{modelAssetPath:new URL('./vendor/pose_landmarker_lite.task',import.meta.url).href,delegate:'CPU'},
    runningMode:'VIDEO',numPoses:1,
  });
  self.postMessage({diagnostic:'pose-ready'});
  } catch(e) {poseInitError='骨架模型加载失败，杠铃跟踪仍可继续';}
  // OpenCV's pinned UMD bundle supports workers through its factory export.
  const response=await fetch(new URL('./vendor/opencv.js',import.meta.url));
  if (!response.ok) throw Error('OpenCV 资源读取失败');
  const source=await response.text();
  const factory=new Function(`${source}; return typeof cv !== 'undefined' ? cv : Module;`)();
  self.postMessage({diagnostic:'opencv-evaluated'});
  // This Emscripten build is a self-resolving thenable; Promise assimilation
  // would recurse indefinitely. Wait for readiness without resolving with it.
  await new Promise((resolve,reject)=>{
    factory.onAbort=reject;
    if(factory.Mat){cv=factory;resolve();}
    else factory.then(ready=>{cv=ready;resolve();});
  });
  self.postMessage({diagnostic:'opencv-ready'});
  tracker=new BarTracker(cv);
}
self.onmessage=async ({data}) => {
  try {
    if (data.method==='init') { await initialize(); self.postMessage({id:data.id,ready:true}); return; }
    if (data.method==='reset') {
      tracker.reset();lastGray?.delete();lastGray=null; last=-1; segment=0; anchored=false; dimensions='';
      // VIDEO requires monotonically increasing timestamps; recreate its temporal state.
      if(pose){await pose.setOptions({runningMode:'IMAGE'}); await pose.setOptions({runningMode:'VIDEO'});}
      self.postMessage({id:data.id,ready:true}); return;
    }
    if(data.method==='mark') {
      if(!lastGray)throw Error('请等待第一个识别帧');
      tracker.update(lastGray,data.anchor);segment++;anchored=true;
      self.postMessage({id:data.id,ready:true});return;
    }
    const started=performance.now(), {bitmap,t,anchor}=data;
    const size=`${bitmap.width}x${bitmap.height}`;
    const gap=last>=0 && (t-last>250 || t<=last || size!==dimensions);
    if (gap) tracker.reset();
    if (anchor) { segment++; anchored=true; }
    last=t; dimensions=size;
    const canvas=new OffscreenCanvas(bitmap.width,bitmap.height), ctx=canvas.getContext('2d',{willReadFrequently:true});
    ctx.drawImage(bitmap,0,0); bitmap.close();
    const rgba=cv.matFromImageData(ctx.getImageData(0,0,canvas.width,canvas.height)), gray=new cv.Mat();
    let point=null, landmarks=[], poseError=poseInitError;
    try {
      cv.cvtColor(rgba,gray,cv.COLOR_RGBA2GRAY);
      point=tracker.update(gray,anchor);
      lastGray?.delete();lastGray=gray.clone();
      try {
        if(pose)landmarks=(pose.detectForVideo(canvas,t).landmarks[0] ?? []).map(p=>({x:p.x,y:p.y,v:Math.min(p.visibility??0,p.presence??1)}));
      } catch (e) { poseError=String(e); }
    } finally { rgba.delete(); gray.delete(); }
    const blob=await canvas.convertToBlob({type:'image/jpeg',quality:.82});
    const bytes=await blob.arrayBuffer();
    self.postMessage({id:data.id,frame:{t,x:point?.x??null,y:point?.y??null,pose:landmarks,segment,
      missingReason:point?null:!anchored?'unmarked':gap?'gap':'lost',
      width:canvas.width,height:canvas.height,processingMs:performance.now()-started,poseError},bytes},[bytes]);
  } catch(e) { data.bitmap?.close(); self.postMessage({id:data.id,error:String(e.message??e)}); }
};
