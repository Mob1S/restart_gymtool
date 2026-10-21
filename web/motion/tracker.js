// lk-fb-template-2: thresholds are engineering defaults, subject to sample validation.
export class BarTracker {
  constructor(cv) { this.cv = cv; this.reset(); }
  reset() {
    this.previous?.delete(); this.template?.delete(); this.previous = this.template = null;
    this.points = []; this.center = null; this.radius = 0;
  }
  patch(gray, center) {
    const cv = this.cv, r = Math.max(3, Math.round(this.radius * .65));
    const x = Math.round(center.x) - r, y = Math.round(center.y) - r;
    if (x < 0 || y < 0 || x + 2*r >= gray.cols || y + 2*r >= gray.rows) return null;
    const view = gray.roi(new cv.Rect(x, y, 2*r+1, 2*r+1));
    const patch = view.clone(); view.delete(); return patch;
  }
  features(gray) {
    const cv = this.cv, mask = cv.Mat.zeros(gray.rows, gray.cols, cv.CV_8UC1), corners = new cv.Mat();
    try {
      cv.circle(mask, new cv.Point(this.center.x, this.center.y), Math.round(this.radius), new cv.Scalar(255), -1);
      cv.goodFeaturesToTrack(gray, corners, 60, .02, 4, mask);
      return Array.from({length: corners.rows}, (_, i) => ({x:corners.data32F[2*i], y:corners.data32F[2*i+1]}));
    } finally { mask.delete(); corners.delete(); }
  }
  update(gray, anchor) {
    const cv = this.cv;
    const median = a => a.sort((a,b)=>a-b)[Math.floor(a.length/2)];
    if (anchor) {
      this.center = {x:anchor.x * gray.cols, y:anchor.y * gray.rows};
      this.radius = anchor.radius * Math.min(gray.cols, gray.rows);
      this.points = this.features(gray);
      this.template?.delete(); this.template = this.patch(gray, this.center);
    } else if (this.previous && this.center && this.points.length >= 4) {
      const from = cv.matFromArray(this.points.length, 1, cv.CV_32FC2, this.points.flatMap(p=>[p.x,p.y]));
      const next = new cv.Mat(), back = new cv.Mat(), status = new cv.Mat(), backStatus = new cv.Mat(), errors = new cv.Mat(), backErrors = new cv.Mat();
      try {
        cv.calcOpticalFlowPyrLK(this.previous, gray, from, next, status, errors);
        cv.calcOpticalFlowPyrLK(gray, this.previous, next, back, backStatus, backErrors);
        const good = this.points.flatMap((p,i) => {
          const x=next.data32F[2*i], y=next.data32F[2*i+1];
          return status.data[i] && backStatus.data[i] && errors.data32F[i]<25 && Math.hypot(p.x-back.data32F[2*i], p.y-back.data32F[2*i+1])<1.5 && x>=0 && y>=0 && x<gray.cols && y<gray.rows ? [{x,y,dx:x-p.x,dy:y-p.y}] : [];
        });
        if (good.length < Math.max(4, Math.ceil(this.points.length*.6))) this.center = null;
        else {
          const dx=median(good.map(p=>p.dx)), dy=median(good.map(p=>p.dy));
          const spread=median(good.map(p=>Math.hypot(p.dx-dx,p.dy-dy)));
          const center={x:this.center.x+dx,y:this.center.y+dy};
          const patch=this.patch(gray,center), score=new cv.Mat();
          let similarity=-1;
          try {
            if (patch && this.template && patch.rows===this.template.rows && patch.cols===this.template.cols) {
              cv.matchTemplate(patch,this.template,score,cv.TM_CCOEFF_NORMED);
              similarity=score.data32F[0];
            }
            this.center = spread>2.5 || Math.hypot(dx,dy)>this.radius || !Number.isFinite(similarity) || similarity<.65 ? null : center;
            if (this.center) {
              this.points=good.map(({x,y})=>({x,y}));
              // Refresh only a validated patch, slowly to limit drift.
              cv.addWeighted(this.template,.95,patch,.05,0,this.template);
              if (this.points.length<12) this.points=this.features(gray);
            }
          } finally { patch?.delete(); score.delete(); }
        }
      } finally { [from,next,back,status,backStatus,errors,backErrors].forEach(m=>m.delete()); }
    } else this.center=null;
    this.previous?.delete(); this.previous=gray.clone();
    return this.center ? {x:this.center.x/gray.cols,y:this.center.y/gray.rows} : null;
  }
}
