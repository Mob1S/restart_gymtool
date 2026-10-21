const db = new Promise((resolve, reject) => {
  const request = indexedDB.open('gym-motion-media', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('files');
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
export async function get(key) {
  const database = await db;
  return new Promise((resolve, reject) => {
    const request = database.transaction('files').objectStore('files').get(key);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
export async function put(key, value) {
  const size = value?.size ?? new Blob([JSON.stringify(value)]).size;
  const estimate = await navigator.storage?.estimate?.();
  if (estimate?.quota && estimate.usage + size > estimate.quota * .95) throw Error('浏览器剩余存储空间不足');
  const database = await db;
  await new Promise((resolve, reject) => {
    const tx = database.transaction('files', 'readwrite');
    tx.objectStore('files').put(value, key);
    tx.oncomplete = resolve;
    tx.onerror = tx.onabort = () => reject(tx.error ?? Error('本地写入失败'));
  });
}
export async function collect(keep, active, results = {}) {
  const database = await db;
  await new Promise((resolve, reject) => {
    const tx = database.transaction('files', 'readwrite');
    const request = tx.objectStore('files').openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      const [folder, file] = String(cursor.key).split('/');
      if (!active.has(folder) && (!keep.includes(folder) || (file !== 'video' && results[folder] && file !== results[folder]))) cursor.delete();
      cursor.continue();
    };
    tx.oncomplete = resolve;
    tx.onerror = tx.onabort = () => reject(tx.error);
  });
}
