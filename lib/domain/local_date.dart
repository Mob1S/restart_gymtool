/// A validated calendar date in the device's local time zone.
///
/// Date keys deliberately contain no time or UTC offset. Queries use [start]
/// and [nextStart] so days with a daylight-saving transition keep their real
/// local boundaries.
class LocalDate {
  final int year;
  final int month;
  final int day;

  const LocalDate._(this.year, this.month, this.day);

  factory LocalDate(int year, int month, int day) {
    final date = _validated(year, month, day);
    if (date == null) {
      throw ArgumentError('Invalid local date: $year-$month-$day');
    }
    return date;
  }

  factory LocalDate.fromDateTime(DateTime value) {
    final local = value.toLocal();
    return LocalDate(local.year, local.month, local.day);
  }

  static final _keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static LocalDate? tryParse(String? value) {
    // Check length too: `$` can match before a trailing newline.
    if (value == null || value.length != 10 || !_keyPattern.hasMatch(value)) {
      return null;
    }
    return _validated(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }

  static LocalDate? _validated(int year, int month, int day) {
    if (year < 0 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return LocalDate._(year, month, day);
  }

  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  DateTime get start => DateTime(year, month, day);

  DateTime get nextStart => DateTime(year, month, day + 1);

  /// Compare civil dates, independent of DST or the length of a local day.
  int daysSince(LocalDate other) => DateTime.utc(year, month, day)
      .difference(DateTime.utc(other.year, other.month, other.day))
      .inDays;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => key;
}
