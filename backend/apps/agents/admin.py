from django.contrib import admin

from .models import AgentAnalysis


@admin.register(AgentAnalysis)
class AgentAnalysisAdmin(admin.ModelAdmin):
    list_display = ("report", "provider", "is_available", "created_at")
    readonly_fields = ("created_at", "updated_at")
