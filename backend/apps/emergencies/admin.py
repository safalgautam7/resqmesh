from django.contrib import admin

from .models import EmergencyReport


@admin.register(EmergencyReport)
class EmergencyReportAdmin(admin.ModelAdmin):
    list_display = ("id", "reporter", "incident_type", "status", "priority", "created_at")
    list_filter = ("status", "priority", "incident_type")
