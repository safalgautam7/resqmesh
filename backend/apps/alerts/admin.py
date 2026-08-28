from django.contrib import admin

from .models import OfficialAlert


@admin.register(OfficialAlert)
class OfficialAlertAdmin(admin.ModelAdmin):
    list_display = ("id", "title", "severity", "status", "created_by", "created_at", "expires_at")
    list_filter = ("severity", "status")
