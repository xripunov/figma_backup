import 'package:flutter/foundation.dart';

class DeepLinkNotifier extends ChangeNotifier {
  String? _groupIdToActivate;

  String? get groupIdToActivate => _groupIdToActivate;

  void activateGroup(String groupId) {
    _groupIdToActivate = groupId;
    notifyListeners();
  }

  void clear() {
    _groupIdToActivate = null;
  }
}
