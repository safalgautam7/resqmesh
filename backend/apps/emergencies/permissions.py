from rest_framework import permissions


class IsReporterOrCoordinator(permissions.BasePermission):
    """Allow object access to the reporter (own record) or coordinators/admins."""

    def has_object_permission(self, request, view, obj):
        user = request.user
        if user.is_coordinator:
            return True
        return obj.reporter_id == user.id
