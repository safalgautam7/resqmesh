from rest_framework import permissions


class IsReporterOrCoordinator(permissions.BasePermission):
    """Allow object access to the reporter (own record) or coordinators/admins."""

    def has_object_permission(self, request, view, obj):
        user = request.user
        if user.is_coordinator:
            return True
        return obj.reporter_id == user.id


class MayDeleteReport(permissions.BasePermission):
    """Deletion is narrowly guarded:
    - the **sender** may always delete their own report (retracting a message
      they sent),
    - **admins / superusers** may delete anything,
    - a normal coordinator (e.g. `coorddemo`) may **not** delete — only the
      owner or an admin can remove a report.
    """

    def has_object_permission(self, request, view, obj):
        user = request.user
        if obj.reporter_id == user.id:
            return True
        if user.is_superuser or user.is_staff or user.is_admin:
            return True
        return False
