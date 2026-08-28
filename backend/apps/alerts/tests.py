from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from .models import OfficialAlert

User = get_user_model()


class OfficialAlertTests(APITestCase):
    def setUp(self):
        self.citizen = User.objects.create_user(username="citizen", password="pass12345")
        self.coordinator = User.objects.create_user(
            username="coord", password="pass12345", role="COORDINATOR"
        )
        self.list_url = reverse("alert-list")

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def _alert(self, **overrides):
        data = {
            "title": "Flood Warning",
            "message": "Move to higher ground.",
            "severity": "WARNING",
            "target_area": "Zone A",
        }
        data.update(overrides)
        return data

    def test_citizen_can_read_active_alerts(self):
        OfficialAlert.objects.create(
            created_by=self.coordinator, title="Flood", message="Move up",
            severity="WARNING",
        )
        self.auth(self.citizen)
        resp = self.client.get(self.list_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data["results"]), 1)

    def test_citizen_cannot_see_expired_alerts(self):
        OfficialAlert.objects.create(
            created_by=self.coordinator, title="Old", message="x", severity="WARNING",
            expires_at=timezone.now() - timedelta(hours=1),
        )
        self.auth(self.citizen)
        resp = self.client.get(self.list_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data["results"]), 0)

    def test_citizen_cannot_see_cancelled_alerts(self):
        OfficialAlert.objects.create(
            created_by=self.coordinator, title="Cancelled", message="x", severity="WARNING",
            status="CANCELLED",
        )
        self.auth(self.citizen)
        resp = self.client.get(self.list_url)
        self.assertEqual(len(resp.data["results"]), 0)

    def test_coordinator_can_see_expired_alerts(self):
        OfficialAlert.objects.create(
            created_by=self.coordinator, title="Old", message="x", severity="WARNING",
            expires_at=timezone.now() - timedelta(hours=1),
        )
        self.auth(self.coordinator)
        resp = self.client.get(self.list_url)
        self.assertEqual(len(resp.data["results"]), 1)

    def test_citizen_cannot_create_official_alert(self):
        self.auth(self.citizen)
        resp = self.client.post(self.list_url, self._alert(), format="json")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_unauthenticated_cannot_create_alert(self):
        resp = self.client.post(self.list_url, self._alert(), format="json")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_coordinator_can_create_alert(self):
        self.auth(self.coordinator)
        resp = self.client.post(self.list_url, self._alert(), format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(OfficialAlert.objects.filter(title="Flood Warning").exists())

    def test_created_by_taken_from_auth_user(self):
        self.auth(self.coordinator)
        resp = self.client.post(self.list_url, self._alert(), format="json")
        alert = OfficialAlert.objects.get(pk=resp.data["id"])
        self.assertEqual(alert.created_by, self.coordinator)

    def test_citizen_cannot_see_created_by_field_injection(self):
        # citizen cannot create at all, so ensure they cannot spoof created_by
        self.auth(self.citizen)
        payload = self._alert()
        payload["created_by"] = self.coordinator.id
        resp = self.client.post(self.list_url, payload, format="json")
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_invalid_severity_rejected(self):
        self.auth(self.coordinator)
        resp = self.client.post(self.list_url, self._alert(severity="CATASTROPHE"), format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
