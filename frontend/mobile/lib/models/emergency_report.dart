class EmergencyReport {
  final int id;
  final int reporter;
  final String reporterName;
  final String description;
  final String incidentType;
  final double? latitude;
  final double? longitude;
  final int? peopleAffected;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmergencyReport({
    required this.id,
    required this.reporter,
    required this.reporterName,
    required this.description,
    required this.incidentType,
    this.latitude,
    this.longitude,
    this.peopleAffected,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmergencyReport.fromJson(Map<String, dynamic> json) => EmergencyReport(
        id: json['id'] as int,
        reporter: json['reporter'] as int,
        reporterName: json['reporter_name'] as String? ?? '',
        description: json['description'] as String,
        incidentType: json['incident_type'] as String? ?? 'OTHER',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        peopleAffected: json['people_affected'] as int?,
        status: json['status'] as String? ?? 'SUBMITTED',
        priority: json['priority'] as String? ?? 'UNASSIGNED',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toCreatePayload() => {
        'description': description,
        'incident_type': incidentType,
        'latitude': latitude,
        'longitude': longitude,
        'people_affected': peopleAffected,
      };
}
