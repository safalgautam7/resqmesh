from rest_framework import mixins, permissions, viewsets

from .models import EmergencyReport
from .permissions import IsReporterOrCoordinator, MayDeleteReport
from .serializers import (
    CoordinatorReportSerializer,
    EmergencyReportDetailSerializer,
    EmergencyReportSerializer,
)
from .services import create_emergency_report


class EmergencyReportViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    mixins.DestroyModelMixin,
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
            if self.action in {"retrieve"}:
                return EmergencyReportDetailSerializer
            return CoordinatorReportSerializer
        return EmergencyReportSerializer

    def check_object_permissions(self, request, obj):
        super().check_object_permissions(request, obj)
        if self.action == "destroy" and not MayDeleteReport().has_object_permission(
            request, self, obj
        ):
            self.permission_denied(
                request,
                message=(
                    "Only the sender of a report or an admin may delete it."
                ),
            )

    def perform_destroy(self, instance):
        instance.delete()

    def perform_create(self, serializer):
        # reporter always comes from authentication
        serializer.save(reporter=self.request.user)
