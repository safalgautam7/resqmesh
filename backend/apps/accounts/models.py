from django.contrib.auth.models import AbstractUser
from django.db import models


class Role(models.TextChoices):
    CITIZEN = "CITIZEN", "Citizen"
    COORDINATOR = "COORDINATOR", "Coordinator"
    ADMIN = "ADMIN", "Admin"


class User(AbstractUser):
    """Custom user for ResQMesh with role-based permissions."""

    role = models.CharField(
        max_length=20,
        choices=Role.choices,
        default=Role.CITIZEN,
    )

    @property
    def is_coordinator(self) -> bool:
        return self.role in (Role.COORDINATOR, Role.ADMIN)

    @property
    def is_admin(self) -> bool:
        return self.role == Role.ADMIN
