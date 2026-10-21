// No images or OCR text leave this origin. Engine and language models are
// bundled at fixed versions; scans work without a third-party OCR service.
(() => {
  const root = new URL('beverage/vendor/', document.baseURI);
  let engine, worker, input, resolvePick, generation = 0;
  const engineReady = () => engine ??= new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL('tesseract.min.js', root);
    script.onload = resolve;
    script.onerror = () => { engine = null; script.remove(); reject(new Error('本地识别引擎未能加载')); };
    document.head.append(script);
  });
  const choose = camera => new Promise(resolve => {
    resolvePick = resolve;
    input = document.createElement('input');
    input.type = 'file'; input.accept = 'image/*';
    if (camera) input.setAttribute('capture', 'environment');
    input.style.display = 'none'; document.body.append(input);
    const done = file => { input?.remove(); input = null; resolvePick = null; resolve(file); };
    input.onchange = () => done(input.files?.[0] ?? null);
    input.oncancel = () => done(null);
    input.click();
  });
  window.gymBeverage = {
    async get(url) {
      const uri = new URL(url);
      if (!['search.openfoodfacts.org', 'world.openfoodfacts.org'].includes(uri.hostname) || uri.protocol !== 'https:') throw new Error('不支持的公共数据源');
      const response = await fetch(uri, { signal: AbortSignal.timeout(15000), credentials: 'omit' });
      if (!response.ok) throw new Error(`公共搜索服务 HTTP ${response.status}`);
      const text = await response.text();
      if (text.length > 2 * 1024 * 1024) throw new Error('公共响应过大');
      return text;
    },
    cancel() {
      generation++;
      input?.remove(); input = null;
      resolvePick?.(null); resolvePick = null;
      worker?.terminate(); worker = null;
    },
    async scan(camera) {
      this.cancel();
      const token = generation;
      const file = await choose(camera);
      if (!file || token !== generation) return 'null';
      if (file.size > 20 * 1024 * 1024) throw new Error('图片不能超过 20 MiB');
      const bitmap = await createImageBitmap(file);
      const pixels = bitmap.width * bitmap.height; bitmap.close();
      if (pixels > 24000000) throw new Error('请使用不超过 2400 万像素的图片');
      let localWorker;
      try {
        await engineReady();
        if (token !== generation) return 'null';
        localWorker = await Tesseract.createWorker(['chi_sim','eng'], 1, {
          workerPath: new URL('worker.min.js', root).href,
          corePath: new URL('core/', root).href,
          langPath: new URL('lang/', root).href,
          workerBlobURL: false,
          gzip: false,
        });
        if (token !== generation) return 'null';
        worker = localWorker;
        const canvas = document.createElement('canvas');
        const image = await createImageBitmap(file);
        canvas.width = image.width; canvas.height = image.height;
        canvas.getContext('2d').drawImage(image, 0, 0); image.close();
        const score = text =>
          (/(能量|热量|energy|calories)/i.test(text) ? 2 : 0) +
          (/\d\s*(kJ|kcal|千焦|千卡|大卡)/i.test(text) ? 2 : 0) +
          (/(每\s*100\s*(ml|毫升)|per\s*100\s*ml|每\s*[份瓶杯])/i.test(text) ? 2 : 0) +
          (/(营养|nutrition)/i.test(text) ? 1 : 0);
        let bestText = '', bestScore = -1;
        // LSTM auto rotation handles skew, not quarter turns. Retry the three
        // other orientations only when label anchors are missing; never infer
        // energy from the image appearance or replace text with guessed values.
        for (const angle of [0, 90, -90, 180]) {
          if (token !== generation) return 'null';
          let candidate = canvas;
          if (angle !== 0) {
            candidate = document.createElement('canvas');
            const swap = Math.abs(angle) === 90;
            candidate.width = swap ? canvas.height : canvas.width;
            candidate.height = swap ? canvas.width : canvas.height;
            const context = candidate.getContext('2d');
            context.translate(candidate.width / 2, candidate.height / 2);
            context.rotate(angle * Math.PI / 180);
            context.drawImage(canvas, -canvas.width / 2, -canvas.height / 2);
          }
          const result = await localWorker.recognize(candidate, {rotateAuto: true});
          const confidence = score(result.data.text);
          if (confidence > bestScore) { bestText = result.data.text; bestScore = confidence; }
          if (angle !== 0) { candidate.width = 0; candidate.height = 0; }
          if (bestScore >= 6) break;
        }
        if (token !== generation) return 'null';
        return JSON.stringify({text: bestText, image: canvas.toDataURL('image/png').split(',')[1]});
      } finally {
        localWorker?.terminate();
        if (worker === localWorker) worker = null;
      }
    },
  };
})();
