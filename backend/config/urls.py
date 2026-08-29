"""Top-level URL configuration for ResQMesh."""

from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/auth/", include("apps.accounts.urls")),
    path("api/v1/emergencies/", include("apps.emergencies.urls")),
    path("api/v1/alerts/", include("apps.alerts.urls")),
    path("api/v1/relay/", include("apps.relay.urls")),
]
