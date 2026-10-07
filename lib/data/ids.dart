import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 新的唯一 id。**全项目只有这一处生成 id**，方便将来换实现
/// （比如换成有序 id、或加前缀便于排查）。
///
/// 放在 `data/ids.dart` 而不是某个仓储文件里：播种、建训练、建组、
/// 建自建动作都要用它，谁都不该为了拿它去 import 一个语义无关的模块。
String newId() => _uuid.v4();
