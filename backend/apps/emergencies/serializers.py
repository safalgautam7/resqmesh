from rest_framework import serializers

from .models import EmergencyReport, IncidentType


def validate_coordinates(attrs):
    lat = attrs.get("latitude")
    lng = attrs.get("longitude")
    if (lat is None) != (lng is None):
        raise serializers.ValidationError(
            "latitude and longitude must be provided together"
        )
    if lat is not None and not (-90 <= lat <= 90):
        raise serializers.ValidationError({"latitude": "Must be between -90 and 90."})
    if lng is not None and not (-180 <= lng <= 180):
        raise serializers.ValidationError({"longitude": "Must be between -180 and 180."})
    return attrs


class EmergencyReportSerializer(serializers.ModelSerializer):
    reporter = serializers.PrimaryKeyRelatedField(read_only=True)
    reporter_name = serializers.CharField(source="reporter.username", read_only=True)

    class Meta:
        model = EmergencyReport
        fields = (
            "id",
            "reporter",
            "reporter_name",
            "description",
            "incident_type",
            "latitude",
            "longitude",
            "location_accuracy",
            "people_affected",
            "status",
            "priority",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("status", "priority")

    def validate(self, attrs):
        incident_type = attrs.get("incident_type")
        if incident_type is not None and incident_type not in IncidentType.values:
            raise serializers.ValidationError({"incident_type": "Invalid incident type."})
        return validate_coordinates(attrs)


class CoordinatorReportSerializer(EmergencyReportSerializer):
    """Coordinator view: allows mutating operational status and priority."""

    class Meta(EmergencyReportSerializer.Meta):
        read_only_fields = ()
