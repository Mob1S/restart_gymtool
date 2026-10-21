import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','web','beverage','vendor');
const manifest=JSON.parse((await readFile(path.join(root,'manifest.json'),'utf8')).replace(/^\uFEFF/,''));
assert.equal(manifest.tesseract,'6.0.1');assert.equal(manifest.core,'6.0.0');assert.equal(manifest.tessdata,'4.1.0');
for (const file of ['tesseract.min.js','worker.min.js','LICENSE-tesseract.js','LICENSE-core','LICENSE-tessdata','lang/chi_sim.traineddata','lang/eng.traineddata',...['','-simd','-lstm','-simd-lstm'].flatMap(v=>[`.wasm.js`,`.wasm`].map(ext=>`core/tesseract-core${v}${ext}`))]) {
  const expected=manifest.files[file];assert(expected,'missing manifest entry '+file);
  const bytes=await readFile(path.join(root,file));assert.equal(bytes.length,expected.bytes,file+' bytes');
  assert.equal(createHash('sha256').update(bytes).digest('hex'),expected.sha256,file+' sha256');
}
console.log('PASS 15 local OCR assets, versions, sizes and SHA-256');
