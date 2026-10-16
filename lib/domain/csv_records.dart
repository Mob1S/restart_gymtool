import 'import_records.dart';

class CsvRecord {
  final int line;
  final List<String> fields;
  CsvRecord(this.line, List<String> fields)
    : fields = List.unmodifiable(fields);
}

/// A strict scanner: malformed quotes make row boundaries unknowable.
List<CsvRecord> scanCsv(String text) {
  final rows = <CsvRecord>[];
  var fields = <String>[];
  var field = StringBuffer();
  var line = 1;
  var start = 1;
  var state = 0; // 0 start, 1 unquoted, 2 quoted, 3 closed quote
  void finishField() {
    fields.add(field.toString());
    field = StringBuffer();
    state = 0;
  }

  void finishRow() {
    finishField();
    if (rows.length >= 100000) {
      throw const ImportValidationException('CSV 超过 100,000 条记录');
    }
    rows.add(CsvRecord(start, fields));
    fields = [];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (state == 0) {
        state = 2;
      } else if (state == 2) {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          state = 3;
        }
      } else {
        throw ImportValidationException('第 $line 行：引号位置无效');
      }
    } else if (c == '\r' || c == '\n') {
      final crlf = c == '\r' && i + 1 < text.length && text[i + 1] == '\n';
      if (state == 2) {
        field.write(crlf ? '\r\n' : c);
      } else {
        finishRow();
      }
      if (crlf) i++;
      line++;
      if (state != 2) start = line;
    } else if (c == ',' && state != 2) {
      finishField();
    } else {
      if (state == 3) throw ImportValidationException('第 $line 行：闭引号后有多余字符');
      field.write(c);
      if (state == 0) state = 1;
    }
  }
  if (state == 2) throw ImportValidationException('第 $start 行：引号未闭合');
  if (field.isNotEmpty || fields.isNotEmpty || state != 0) finishRow();
  return List.unmodifiable(rows);
}
