import 'dart:convert';

Map<String, Object?> checkedObject(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((k) => k is! String) ||
      value.keys.any((k) => !keys.contains(k))) {
    throw const FormatException('训练数据字段无效');
  }
  return value.cast<String, Object?>();
}

int checkedInt(Object? value, {int min = 0, int max = 8640000000000000}) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('训练数据整数超出范围');
  }
  return value;
}

String checkedText(Object? value, {bool empty = true, int max = 5000}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty)) {
    throw const FormatException('训练数据文本无效');
  }
  return value;
}

List<Object?> checkedList(Object? value, {int max = 100000}) {
  if (value is! List || value.length > max) {
    throw const FormatException('训练数据列表无效');
  }
  return value.cast<Object?>();
}

bool checkedBool(Object? value) {
  if (value is! bool) throw const FormatException('训练数据布尔值无效');
  return value;
}

Object? decodeTrainingJson(String value) {
  if (value.length > 20 * 1024 * 1024) throw const FormatException('训练数据过大');
  return jsonDecode(value);
}
