class OfficialAlert {
  final int id;
  final String title;
  final String message;
  final String severity;
  final String targetArea;
  final String status;
  final String effectiveStatus;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? expiresAt;

  OfficialAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.targetArea,
    required this.status,
    required this.effectiveStatus,
    required this.createdByName,
    required this.createdAt,
    this.expiresAt,
  });

  factory OfficialAlert.fromJson(Map<String, dynamic> json) => OfficialAlert(
        id: json['id'] as int,
        title: json['title'] as String,
        message: json['message'] as String,
        severity: json['severity'] as String? ?? 'WARNING',
        targetArea: json['target_area'] as String? ?? '',
        status: json['status'] as String? ?? 'ACTIVE',
        effectiveStatus: json['effective_status'] as String? ?? json['status'] ?? 'ACTIVE',
        createdByName: json['created_by_name'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
      );
}
