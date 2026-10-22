// The host loads feature code only when a capability is first used. Failed
// scripts are removed so a subsequent user action can retry the same resource.
(() => {
  const resources = {
    motion: { path: 'motion/runtime.js', type: 'module', global: 'gymMotion' },
    beverage: { path: 'beverage/runtime.js', global: 'gymBeverage' },
  };
  const pending = new Map();
  const disabled = new Set();
  window.gymPluginRuntime = {
    async activate(id) {
      const resource = resources[id];
      if (!resource) throw new Error('未知插件资源');
      disabled.delete(id);
      if (pending.has(id)) await pending.get(id);
      const runtime = window[resource.global];
      if (id === 'motion' && runtime) await runtime.call('activate', '{}');
      if (id === 'beverage' && runtime) runtime.activate();
    },
    load(id) {
      const resource = resources[id];
      if (!resource) return Promise.reject(new Error('未知插件资源'));
      if (disabled.has(id)) return Promise.reject(new Error('插件已停用'));
      if (pending.has(id)) return pending.get(id);
      if (window[resource.global]) return Promise.resolve();
      const script = document.createElement('script');
      script.src = new URL(resource.path, document.baseURI).href;
      if (resource.type) script.type = resource.type;
      const task = new Promise((resolve, reject) => {
        script.onload = () => {
          if (window[resource.global]) resolve();
          else reject(new Error('插件资源未能初始化'));
        };
        script.onerror = () => reject(new Error('插件资源未能加载，请重试'));
      }).catch(error => {
        if (pending.get(id) === task) pending.delete(id);
        script.remove();
        throw error;
      });
      pending.set(id, task);
      document.head.append(script);
      return task;
    },
    async deactivate(id) {
      const resource = resources[id];
      if (!resource) throw new Error('未知插件资源');
      disabled.add(id);
      // If a load was already requested, wait for it before closing the result.
      // Do not introduce a feature load just because the user disables it.
      if (pending.has(id)) {
        try { await pending.get(id); }
        catch { return; } // A failed load owns no runtime resources.
      }
      const runtime = window[resource.global];
      if (id === 'motion' && runtime) await runtime.call('deactivate', '{}');
      if (id === 'beverage' && runtime) await runtime.deactivate();
    },
    async cancel(id) {
      const resource = resources[id];
      if (!resource) throw new Error('未知插件资源');
      if (pending.has(id)) {
        try { await pending.get(id); } catch { return; }
      }
      const runtime = window[resource.global];
      if (id === 'motion' && runtime) await runtime.call('cancel', '{}');
      if (id === 'beverage' && runtime) await runtime.cancel();
    },
    async cancelSearch(sessionId) {
      if(pending.has('beverage')) {try {await pending.get('beverage');} catch {return;}}
      if(window.gymBeverage) await window.gymBeverage.cancelSearch(sessionId);
    },
  };
})();
