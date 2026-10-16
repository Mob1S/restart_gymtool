import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'data_revision.dart';

/// Shell navigators retain their keyed pages. Refresh data explicitly when a
/// committed mutation changes the revision, including while a detail is open.
mixin DataRevisionLoader<T extends StatefulWidget> on State<T> {
  int? _loadedRevision;
  Future<void> reloadData();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final value = context.watch<DataRevision?>()?.value ?? 0;
    if (_loadedRevision == value) return;
    _loadedRevision = value;
    reloadData();
  }
}
