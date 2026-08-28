from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

User = get_user_model()


class RegisterTests(APITestCase):
    url = reverse("register")

    def test_registration_succeeds_with_valid_data(self):
        resp = self.client.post(
            self.url,
            {"username": "alice", "email": "alice@example.com", "password": "strongpass123"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username="alice").exists())
        self.assertEqual(resp.data["role"], "CITIZEN")

    def test_duplicate_username_is_rejected(self):
        User.objects.create_user(username="alice", password="strongpass123")
        resp = self.client.post(
            self.url,
            {"username": "alice", "password": "strongpass123"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_short_password_is_rejected(self):
        resp = self.client.post(
            self.url,
            {"username": "bob", "password": "short"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_citizen_cannot_gain_coordinator_role_via_payload(self):
        resp = self.client.post(
            self.url,
            {
                "username": "mal",
                "password": "strongpass123",
                "role": "COORDINATOR",
                "is_staff": True,
                "is_superuser": True,
            },
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(username="mal")
        self.assertEqual(user.role, "CITIZEN")
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)


class LoginTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="alice", password="strongpass123")

    def test_valid_login_returns_tokens(self):
        resp = self.client.post(
            reverse("login"),
            {"username": "alice", "password": "strongpass123"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)

    def test_invalid_credentials_are_rejected(self):
        resp = self.client.post(
            reverse("login"),
            {"username": "alice", "password": "wrongpassword"},
            format="json",
        )
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_returns_authenticated_user(self):
        self.client.force_authenticate(user=self.user)
        resp = self.client.get(reverse("me"))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data["username"], "alice")

    def test_me_requires_authentication(self):
        resp = self.client.get(reverse("me"))
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)
