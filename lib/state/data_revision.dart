import 'package:flutter/foundation.dart';

class DataRevision extends ChangeNotifier {
  int _value = 0;
  int get value => _value;
  void changed() {
    _value++;
    notifyListeners();
  }
}
