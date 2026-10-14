class AppSession {
  final int? id;
  final String appName;
  final String exePath;
  final DateTime startTime;
  final DateTime endTime;

  AppSession({
    this.id,
    required this.appName,
    required this.exePath,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'appName': appName,
      'exePath': exePath,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
    };
  }

  factory AppSession.fromMap(Map<String, dynamic> map) {
    return AppSession(
      id: map['id'],
      appName: map['appName'],
      exePath: map['exePath'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int),
    );
  }

  Duration get duration => endTime.difference(startTime);
}
