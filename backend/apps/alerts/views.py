from django.db.models import Q
from django.utils import timezone

from apps.accounts.permissions import IsCoordinatorOrAdmin
from rest_framework import mixins, permissions, viewsets

from .models import AlertStatus, OfficialAlert
from .serializers import OfficialAlertSerializer
from .services import notify_alert_created


class OfficialAlertViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    queryset = OfficialAlert.objects.select_related("created_by").all().order_by("-created_at")
    serializer_class = OfficialAlertSerializer

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [permissions.IsAuthenticated()]
        # create/update require an authorized coordinator/admin
        return [permissions.IsAuthenticated(), IsCoordinatorOrAdmin()]

    def get_queryset(self):
        user = self.request.user
        if user.is_coordinator:
            return self.queryset
        # citizens only see currently-active, non-expired alerts
        now = timezone.now()
        return self.queryset.filter(
            Q(status=AlertStatus.ACTIVE)
            & (Q(expires_at__isnull=True) | Q(expires_at__gt=now))
        )

    def perform_create(self, serializer):
        alert = serializer.save(created_by=self.request.user)
        notify_alert_created(alert)
