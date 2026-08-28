from django.conf import settings
from django.db import models


class AgentAnalysis(models.Model):
    """Result of running the multi-agent workflow on an emergency report.

    The original report is never modified by the agents; structured analysis is
    stored here and exposed to coordinators for review (M9).
    """

    report = models.OneToOneField(
        "emergencies.EmergencyReport",
        on_delete=models.CASCADE,
        related_name="analysis",
    )

    extraction = models.JSONField(default=dict, blank=True)
    uncertainty = models.JSONField(default=dict, blank=True)
    priority = models.JSONField(default=dict, blank=True)
    duplicate = models.JSONField(default=dict, blank=True)

    provider = models.CharField(max_length=50, default="mock")
    model = models.CharField(max_length=100, blank=True, default="")
    is_available = models.BooleanField(default=False)
    error = models.TextField(blank=True, default="")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Agent analysis"
        verbose_name_plural = "Agent analyses"

    def __str__(self):
        return f"Analysis({self.report_id}, avail={self.is_available})"

    def suggested_priority(self):
        return self.priority.get("suggested_priority")

    def suggested_incident_type(self):
        return self.extraction.get("incident_type")

    def uncertainty_score(self):
        return self.uncertainty.get("uncertainty_score")
