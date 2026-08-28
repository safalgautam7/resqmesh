from rest_framework import mixins, permissions, viewsets

from .models import EmergencyReport
from .permissions import IsReporterOrCoordinator
from .serializers import (
    CoordinatorReportSerializer,
    EmergencyReportSerializer,
)
from .services import create_emergency_report


class EmergencyReportViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    queryset = EmergencyReport.objects.select_related("reporter").all().order_by("-created_at")
    permission_classes = [permissions.IsAuthenticated, IsReporterOrCoordinator]

    def get_queryset(self):
        user = self.request.user
        if user.is_coordinator:
            return self.queryset
        return self.queryset.filter(reporter=user)

    def get_serializer_class(self):
        if self.request.user.is_coordinator:
            return CoordinatorReportSerializer
        return EmergencyReportSerializer

    def perform_create(self, serializer):
        # reporter always comes from authentication
        serializer.save(reporter=self.request.user)
