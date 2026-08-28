import 'agent_analysis.dart';

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
  final AgentAnalysis? analysis;

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
    this.analysis,
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

  factory EmergencyReport.fromJsonDetail(Map<String, dynamic> json) {
    final base = EmergencyReport.fromJson(json);
    return EmergencyReport(
      id: base.id,
      reporter: base.reporter,
      reporterName: base.reporterName,
      description: base.description,
      incidentType: base.incidentType,
      latitude: base.latitude,
      longitude: base.longitude,
      peopleAffected: base.peopleAffected,
      status: base.status,
      priority: base.priority,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      analysis: (json['analysis'] as Map?) == null
          ? null
          : AgentAnalysis.fromJson((json['analysis'] as Map).cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toCreatePayload() => {
        'description': description,
        'incident_type': incidentType,
        'latitude': latitude,
        'longitude': longitude,
        'people_affected': peopleAffected,
      };
}
