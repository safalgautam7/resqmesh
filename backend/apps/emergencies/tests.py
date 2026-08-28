from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import EmergencyReport

User = get_user_model()


class EmergencyReportTests(APITestCase):
    def setUp(self):
        self.citizen = User.objects.create_user(username="citizen", password="pass12345")
        self.citizen2 = User.objects.create_user(username="citizen2", password="pass12345")
        self.coordinator = User.objects.create_user(
            username="coord", password="pass12345", role="COORDINATOR"
        )
        self.list_url = reverse("emergency-list")

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def _create(self, description="We are trapped in a building", incident_type="TRAPPED",
                latitude=None, longitude=None):
        return {
            "description": description,
            "incident_type": incident_type,
            "latitude": latitude,
            "longitude": longitude,
            "people_affected": 4,
        }

    def test_create_emergency_report(self):
        self.auth(self.citizen)
        resp = self.client.post(self.list_url, self._create(), format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(EmergencyReport.objects.filter(reporter=self.citizen).exists())

    def test_reporter_is_autoset_from_auth(self):
        self.auth(self.citizen)
        payload = self._create()
        payload["reporter"] = self.citizen2.id  # client cannot set another as reporter
        resp = self.client.post(self.list_url, payload, format="json")
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data["reporter"], self.citizen.id)

    def test_required_description_validated(self):
        self.auth(self.citizen)
        resp = self.client.post(self.list_url, {"incident_type": "FIRE"}, format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_incident_type_rejected(self):
        self.auth(self.citizen)
        resp = self.client.post(self.list_url, self._create(incident_type="ALIEN"), format="json")
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_coordinates_rejected(self):
        self.auth(self.citizen)
        resp = self.client.post(
            self.list_url, self._create(latitude=200, longitude=10), format="json"
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unauthenticated_cannot_create_report(self):
        resp = self.client.post(self.list_url, self._create(), format="json")
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_list_own_reports_only(self):
        EmergencyReport.objects.create(
            reporter=self.citizen, description="mine", incident_type="FIRE"
        )
        EmergencyReport.objects.create(
            reporter=self.citizen2, description="theirs", incident_type="FLOOD"
        )
        self.auth(self.citizen)
        resp = self.client.get(self.list_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        ids = [r["id"] for r in resp.data["results"]]
        self.assertEqual(len(ids), 1)
        self.assertEqual(EmergencyReport.objects.get(pk=ids[0]).reporter, self.citizen)

    def test_get_own_report(self):
        report = EmergencyReport.objects.create(
            reporter=self.citizen, description="mine", incident_type="FIRE"
        )
        self.auth(self.citizen)
        resp = self.client.get(reverse("emergency-detail", args=[report.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["description"], "mine")

    def test_citizen_cannot_view_other_report(self):
        report = EmergencyReport.objects.create(
            reporter=self.citizen2, description="theirs", incident_type="FLOOD"
        )
        self.auth(self.citizen)
        resp = self.client.get(reverse("emergency-detail", args=[report.id]))
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_coordinator_can_view_all_reports(self):
        EmergencyReport.objects.create(
            reporter=self.citizen, description="a", incident_type="FIRE"
        )
        EmergencyReport.objects.create(
            reporter=self.citizen2, description="b", incident_type="FLOOD"
        )
        self.auth(self.coordinator)
        resp = self.client.get(self.list_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data["results"]), 2)

    def test_coordinator_can_update_status(self):
        report = EmergencyReport.objects.create(
            reporter=self.citizen, description="a", incident_type="FIRE"
        )
        self.auth(self.coordinator)
        resp = self.client.patch(
            reverse("emergency-detail", args=[report.id]),
            {"status": "REVIEWING"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        report.refresh_from_db()
        self.assertEqual(report.status, "REVIEWING")

    def test_coordinator_can_update_priority(self):
        report = EmergencyReport.objects.create(
            reporter=self.citizen, description="a", incident_type="FIRE"
        )
        self.auth(self.coordinator)
        resp = self.client.patch(
            reverse("emergency-detail", args=[report.id]),
            {"priority": "HIGH"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        report.refresh_from_db()
        self.assertEqual(report.priority, "HIGH")

    def test_citizen_cannot_change_priority(self):
        report = EmergencyReport.objects.create(
            reporter=self.citizen, description="a", incident_type="FIRE",
            priority="MEDIUM",
        )
        self.auth(self.citizen)
        resp = self.client.patch(
            reverse("emergency-detail", args=[report.id]),
            {"priority": "CRITICAL", "status": "RESOLVED"},
            format="json",
        )
        report.refresh_from_db()
        self.assertEqual(report.priority, "MEDIUM")
        self.assertEqual(report.status, "SUBMITTED")
        # still 200 because read-only fields are ignored
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_timestamps_are_server_generated(self):
        self.auth(self.citizen)
        resp = self.client.post(self.list_url, self._create(), format="json")
        self.assertIsNotNone(resp.data["created_at"])
        self.assertIsNotNone(resp.data["updated_at"])
