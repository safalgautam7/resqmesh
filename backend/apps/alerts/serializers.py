from rest_framework import serializers

from .models import AlertSeverity, OfficialAlert


class OfficialAlertSerializer(serializers.ModelSerializer):
    created_by = serializers.PrimaryKeyRelatedField(read_only=True)
    created_by_name = serializers.CharField(source="created_by.username", read_only=True)
    effective_status = serializers.CharField(read_only=True)

    class Meta:
        model = OfficialAlert
        fields = (
            "id",
            "title",
            "message",
            "severity",
            "target_area",
            "status",
            "effective_status",
            "created_by",
            "created_by_name",
            "created_at",
            "expires_at",
        )
        read_only_fields = ("created_by",)

    def validate_severity(self, value):
        if value not in AlertSeverity.values:
            raise serializers.ValidationError("Invalid severity.")
        return value
