from rest_framework import permissions


class IsCoordinatorOrAdmin(permissions.BasePermission):
    """Allow only coordinators and admins."""

    message = "This action requires an authorized coordinator account."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_coordinator)


class IsAdminOnly(permissions.BasePermission):
    """Allow only admins."""

    message = "This action requires an administrator account."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_admin)
