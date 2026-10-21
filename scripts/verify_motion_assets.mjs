import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../web/motion/vendor/',import.meta.url);
const manifest=JSON.parse(await readFile(new URL('manifest.json',root),'utf8'));
for(const [file,expected] of Object.entries(manifest.sha256)) {
  const actual=createHash('sha256').update(await readFile(new URL(file,root))).digest('hex');
  if(actual!==expected)throw Error(`Motion asset hash mismatch: ${file}`);
}
console.log(`Verified ${Object.keys(manifest.sha256).length} pinned motion assets`);
