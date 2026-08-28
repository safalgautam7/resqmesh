class AgentAnalysis {
  final Map<String, dynamic> extraction;
  final Map<String, dynamic> uncertainty;
  final Map<String, dynamic> priority;
  final Map<String, dynamic> duplicate;
  final String provider;
  final String model;
  final bool isAvailable;
  final String? suggestedPriority;

  AgentAnalysis({
    required this.extraction,
    required this.uncertainty,
    required this.priority,
    required this.duplicate,
    required this.provider,
    required this.model,
    required this.isAvailable,
    this.suggestedPriority,
  });

  factory AgentAnalysis.fromJson(Map<String, dynamic> json) {
    final priorityMap = (json['priority'] as Map?) ?? {};
    return AgentAnalysis(
      extraction: (json['extraction'] as Map?)?.cast<String, dynamic>() ?? {},
      uncertainty: (json['uncertainty'] as Map?)?.cast<String, dynamic>() ?? {},
      priority: priorityMap.cast<String, dynamic>(),
      duplicate: (json['duplicate'] as Map?)?.cast<String, dynamic>() ?? {},
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      isAvailable: json['is_available'] as bool? ?? false,
      suggestedPriority:
          json['suggested_priority'] as String? ?? priorityMap['suggested_priority'] as String?,
    );
  }

  String get incidentType =>
      (extraction['incident_type'] as String?) ?? 'OTHER';
  int? get peopleAffected => extraction['people_affected'] as int?;
  String? get locationHint => extraction['location_hint'] as String?;
  double get uncertaintyScore =>
      (uncertainty['uncertainty_score'] as num?)?.toDouble() ?? 0.0;
  String get uncertaintyLevel =>
      (uncertainty['level'] as String?) ?? 'UNKNOWN';
  String get confidenceText =>
      (priority['confidence'] as num?)?.toStringAsFixed(2) ?? 'n/a';
  String get rationale => priority['rationale'] as String? ?? '';
}
