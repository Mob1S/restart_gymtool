import 'types.dart';

class SessionDeletePreview {
  final WorkoutSession session;
  final int completedSets;
  final int pendingSets;
  final String token;
  const SessionDeletePreview(
    this.session,
    this.completedSets,
    this.pendingSets,
    this.token,
  );
}

class SessionDeleteResult {
  final bool deleted;
  final String sessionId;
  final bool wasActive;
  const SessionDeleteResult(this.deleted, this.sessionId, this.wasActive);
}

class RecordManagementException implements Exception {
  final String message;
  const RecordManagementException(this.message);
  @override
  String toString() => message;
}
