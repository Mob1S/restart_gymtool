# 插件开发接口

首期插件随 App 编译发布，在设置中的“插件管理”启停。基础训练 `gym.training` 必需；新安装默认关闭 `gym.calories` 和 `gym.motion`，旧安装升级保留两项功能。停用保留数据、媒体和本机设置。插件仍占安装包空间，目前没有独立下载安装或市场。

## 接入一个插件

公共接口位于 `lib/plugins/api/`，不依赖 Flutter、数据库或文件 API。清单使用稳定 ID、版本、支持平台、必需与可选能力、依赖和 API 范围。协议版本 `pluginApiVersion` 为 1。`PluginRuntime` 实现 `start`、`invoke`、`cancel`、`prepareStop` 和 `stop`。把 `PluginDefinition(manifest: ..., createRuntime: ...)` 加入 `StaticPluginCatalog` 即可参与现有管理流程。

生产目录唯一入口为 `lib/plugins/bundled/bundled_catalog.dart`。`PluginDefinition.supportedDataVersions` 默认 `{1}`；组合层通过管理器的 `validateData(definition)` 检查本机命名空间版本，不兼容时在创建宿主和运行实例之前拒绝激活，保留原数据。页面、路由、导航和训练组操作放在 Flutter adapter；公共协议中不传 `Widget`、`BuildContext`、控制器或纹理。`test/plugins/example_plugin.dart` 展示通过公共宿主保存 preferences 文档并订阅事件，`plugin_composition_test.dart` 使用两个不同 ID 验证相同宿主逻辑，无需在管理器增加 ID 分支。示例不进入生产目录。

```dart
await host.request('storage.private.write', {
  'dataVersion': 1,
  'operations': [
    {'key': 'preferences', 'value': {'displayUnit': 'kg'}},
  ],
});
final preferences = await host.request('storage.private.read', {
  'key': 'preferences',
});
```

宿主自动绑定 pluginId，插件不得选择其他命名空间。批量写入在一个事务内完成；参数、JSON 值和实例有效性在写入与提交前检查。JSON 允许 null、布尔、有限数、字符串、列表、字符串键对象，最大嵌套深度 32；时间使用 Unix 毫秒，实体使用稳定 ID。资源通过句柄引用，不把视频或逐帧图片装进控制消息。

## 能力与身份

声明能力不代表获得授权。宿主用 `BoundPluginHost` 的 `HostMethod` 和 `HostTopic` 显式注册服务，检查授权后再进入处理器。实际控制调用透明构造 `PluginRequest`，包含唯一 requestId、protocolVersion 与实例 generation，业务处理器接收的 arguments 保持原样。订阅产生 `PluginEvent` 对象，包含订阅 requestId、实例 generation、主题 type 与 payload；消费方从 payload 读取事件业务数据。每个运行实例有独立 `PluginScope` token；撤销后拒绝新请求并丢弃旧结果和事件。普通请求超时还会取消请求标识，事务提交检查拒绝该请求的晚写入。官方 calories/motion 兼容服务也走该分派器，不向插件传 `SqlExecutor`。

处理器自身必须检查参数语义；写服务必须把 scope 检查放在事务内提交之前，以回滚撤销期间的在途写入。一般资源、订阅和事件注册应加入 `scope.addCleanup`。事件主题应绑定调用者身份；不要把其他命名空间的事件源交给插件。网络是热量插件的可选能力，拒绝网络不妨碍手动录入或使用个人库。

## 生命周期与错误

管理器串行处理启停，区分本机 desired_enabled 与实际状态。启用先启动实例、保存偏好，再发布 enabled；保存失败回收刚启动的实例。停用先检查 `prepareStop`；busy 或 unsavedChanges 保持启用并提示返回页面处理，不能暗中丢弃编辑。确认关闭资源后才发布 disabled。关闭失败显示 failed，保留错误并允许重试；若偏好落库失败而资源已经关闭，实际状态仍为 disabled，同时报告 storageFailure。

普通 start/stop、控制请求超时为 10 秒。超时撤销新请求，尝试确认资源关闭，不能把超时当作已停止的证据。长媒体任务通过进度与显式取消管理；注册 `HostMethod(control: false, ...)`，不使用普通控制超时。取消或 generation 换代后忽略旧事件。页面应等待 closeSession 完成；Widget dispose 只作幂等兜底。

错误码为 unsupportedApi、unsupportedPlatform、missingDependency、permissionDenied、pluginDisabled、busy、unsavedChanges、cancelled、timeout、storageFailure、invalidData、internalError。界面使用中文说明，不把内部路径作为用户错误信息。

恢复使用 `PluginManager.runWithPluginsPaused`：先检查所有安全点，暂停基础训练实例的能力请求并保持训练 UI 和控制器运行；关闭可选插件的运行资源，在串行队列内恢复事务，最后重新启动原运行插件、恢复请求，不更改启用偏好。恢复失败也会尝试恢复原运行状态，个别启动失败由插件状态报告。

## 数据和备份

本机 schema 12 将启用偏好与扩展数据分别保存。通用私有文档的每个命名空间只允许一个 dataVersion；不兼容的版本需要宿主事务迁移，不能覆盖原始数据。备份 v8 保留已有训练和饮料字段，新增 plugins 封装；保留 ID `gym.training`、`gym.calories`、`gym.motion` 不得重复出现在扩展区。

扩展封装包含 dataVersion 与 records（key/value）。未知插件数据不执行，完整保留并可再次导出。缺失 ID 保留本机命名空间；显式空 records 清空该命名空间并保留版本。v1–v7 没有 plugins 时保留本机扩展数据。启用选择不随训练备份覆盖。20 MiB、100,000 条总记录限制也包含扩展数据。

动作分析视频和结果仍不在 JSON 备份中；停用保留本机文件，恢复训练记录解除原训练组关联。不要将插件备份表述为视频备份。

## 边界与后续

同进程接口约束用于维护结构和受控异步错误隔离，不是对恶意 Dart 代码的安全沙箱，无法隔离无限循环或原生崩溃。独立安装仍需来源验证、下载与安装事务、受限执行环境、跨进程权限、资源限额和版本回退设计。现有 catalog、manifest、JSON 协议、runtime、绑定身份宿主、数据版本和 Flutter adapter 是后续接入点，不代表这些能力已实现。

运行 `flutter test test/plugins test/layering_test.dart` 验证协议、清单、生命周期、能力隔离和示例组合。Web/Android 构建不能替代真机相机释放、权限拒绝、切后台和媒体保留验收；具体验证结果记录在实施验收文档中。
