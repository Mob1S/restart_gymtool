// Enable compiled features through their guarded UI, in isolated test profiles.
export async function enableBundledPlugins(h, routes = ['/calories', '/analysis']) {
  for (const route of routes) {
    await h.send('Page.navigate', {url:h.origin+'/#'+route});
    await h.until(async()=>await h.has('启用并继续') || await h.has(route==='/calories'?'已记录饮料热量':'看见每一次动作'), 'plugin route ready');
    if(await h.has('启用并继续')) await h.clickText('启用并继续',true);
    await h.expectText(route==='/calories'?'已记录饮料热量':'看见每一次动作');
  }
}
