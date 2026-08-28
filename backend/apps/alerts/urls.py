from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import OfficialAlertViewSet

router = DefaultRouter()
router.register("", OfficialAlertViewSet, basename="alert")

urlpatterns = [
    path("", include(router.urls)),
]
