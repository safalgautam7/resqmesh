from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings

from apps.agents.models import AgentAnalysis
from apps.agents.providers import get_provider
from apps.agents.providers.mock import MockProvider
from apps.agents import schemas, services
from apps.emergencies.models import EmergencyReport
from apps.emergencies.services import create_emergency_report

User = get_user_model()


class MockProviderTests(TestCase):
    def test_extraction(self):
        p = MockProvider()
        out = p.generate_json("EXTRACTION AGENT.\nReport: We are trapped in a damaged building near KU, four people, one bleeding badly.", seed=1)
        self.assertEqual(out["incident_type"], "BUILDING_COLLAPSE")
        self.assertEqual(out["people_affected"], 4)
        self.assertIn("bleeding", [i["type"] for i in out["injuries"]])
        self.assertEqual(out["location_hint"], "KU")

    def test_uncertainty_flags_hedged_language(self):
        p = MockProvider()
        out = p.generate_json("UNCERTAINTY AGENT.\nReport: I think there are maybe ten people, not sure if anyone is hurt.", seed=1)
        self.assertGreaterEqual(out["uncertainty_score"], 0.4)

    def test_priority_bleeding_is_critical(self):
        p = MockProvider()
        out = p.generate_json("PRIORITY AGENT.\nReport: A man is bleeding badly and unconscious.", seed=1)
        self.assertEqual(out["suggested_priority"], "CRITICAL")

    def test_deterministic_given_seed(self):
        p = MockProvider()
        a = p.generate_json("PRIORITY AGENT.\nReport: fire smoke everywhere", seed=7)
        b = p.generate_json("PRIORITY AGENT.\nReport: fire smoke everywhere", seed=7)
        self.assertEqual(a, b)


class NormalizationTests(TestCase):
    def test_coerces_bad_incident_type(self):
        out = schemas.normalize_extraction({"incident_type": "ALIEN_ATTACK", "people_affected": "twelve"})
        self.assertEqual(out["incident_type"], "OTHER")
        self.assertIsNone(out["people_affected"])

    def test_coerces_priority(self):
        out = schemas.normalize_priority({"suggested_priority": "urgent!!", "confidence": 2})
        self.assertEqual(out["suggested_priority"], "UNASSIGNED")
        self.assertLessEqual(out["confidence"], 1.0)

    def test_defaults_on_non_dict(self):
        self.assertEqual(schemas.normalize_uncertainty(None)["level"] in {"LOW", "MEDIUM", "HIGH"}, True)


class WorkflowTests(TestCase):
    def setUp(self):
        self.u = User.objects.create_user(username="agentcit", password="x")
        self.coord = User.objects.create_user(username="agentcoord", password="x", role="COORDINATOR")

    def test_report_creation_triggers_analysis(self):
        r = create_emergency_report(
            reporter=self.u,
            description="We are trapped in a collapsing building near the market, five people, one badly bleeding.",
            incident_type="OTHER",
        )
        analysis = AgentAnalysis.objects.get(report=r)
        self.assertTrue(analysis.is_available)
        self.assertEqual(analysis.suggested_incident_type(), "BUILDING_COLLAPSE")
        self.assertEqual(analysis.suggested_priority(), "CRITICAL")
        self.assertGreaterEqual(analysis.uncertainty_score(), 0.0)
        self.assertIsNotNone(analysis.extraction.get("location_hint"))

    def test_analysis_idempotent_by_default(self):
        r = create_emergency_report(reporter=self.u, description="fire smoke", incident_type="FIRE")
        a1 = services.analyze_report(r)
        a2 = services.analyze_report(r)
        self.assertEqual(a1.pk, a2.pk)

    def test_failing_provider_never_breaks_ingestion(self):
        class Boom(MockProvider):
            def generate_json(self, *a, **k):
                raise RuntimeError("model down")

        with override_settings(AI_PROVIDER="mock"), mock.patch(
            "apps.agents.services.get_provider", return_value=Boom()
        ):
            # report still created even though every agent raises
            r = create_emergency_report(reporter=self.u, description="trapped help", incident_type="OTHER")
        self.assertEqual(EmergencyReport.objects.get(pk=r.pk).pk, r.pk)
        a = AgentAnalysis.objects.get(report=r)
        self.assertFalse(a.is_available)
        self.assertIn("error", a.extraction)

    def test_analysis_exposed_to_coordinator_via_api(self):
        from rest_framework.test import APIClient

        r = create_emergency_report(reporter=self.u, description="bleeding badly unconscious", incident_type="OTHER")
        client = APIClient()
        client.force_authenticate(self.coord)
        resp = client.get(f"/api/v1/emergencies/{r.pk}/")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("analysis", resp.data)
        self.assertIn("extraction", resp.data["analysis"])
        self.assertIn("suggested_priority", resp.data["analysis"])

    def test_provider_factory_defaults_to_mock(self):
        self.assertIsInstance(get_provider(), MockProvider)


class SafetyFloorTests(TestCase):
    def test_bleeding_floors_to_critical(self):
        extraction = {"incident_type": "MEDICAL", "injuries": [{"type": "bleeding"}]}
        pri = {"suggested_priority": "MEDIUM", "confidence": 0.6, "rationale": "mild"}
        out = services._apply_safety_floor(pri, extraction)
        self.assertEqual(out["suggested_priority"], "CRITICAL")
        self.assertIn("safety floor", out["rationale"])

    def test_collapse_floors_to_high(self):
        extraction = {"incident_type": "BUILDING_COLLAPSE", "injuries": []}
        pri = {"suggested_priority": "MEDIUM", "confidence": 0.5, "rationale": ""}
        out = services._apply_safety_floor(pri, extraction)
        self.assertEqual(out["suggested_priority"], "HIGH")

    def test_never_downgrades(self):
        extraction = {"incident_type": "FIRE", "injuries": []}
        pri = {"suggested_priority": "CRITICAL", "confidence": 0.8, "rationale": ""}
        out = services._apply_safety_floor(pri, extraction)
        self.assertEqual(out["suggested_priority"], "CRITICAL")

    def test_benign_report_keeps_low_priority(self):
        extraction = {"incident_type": "OTHER", "injuries": []}
        pri = {"suggested_priority": "LOW", "confidence": 0.7, "rationale": ""}
        out = services._apply_safety_floor(pri, extraction)
        self.assertEqual(out["suggested_priority"], "LOW")


class EvaluationTests(TestCase):
    def test_mock_harness_returns_metrics(self):
        from apps.agents import evaluation

        report = evaluation.evaluate_cases(get_provider())
        self.assertEqual(report["total"], len(evaluation.EVAL_CASES))
        self.assertIn("incident_accuracy", report)
        self.assertEqual(len(report["rows"]), len(evaluation.EVAL_CASES))

    def test_agents_outperform_baseline_priority(self):
        from apps.agents import evaluation

        value = evaluation.analyze_pipeline_value(get_provider())
        # Agent pipeline with safety floor should not be worse than baseline
        self.assertGreaterEqual(value["agent_priority_ok"], value["baseline_priority_ok"])

    def test_baseline_classifier_runs(self):
        from apps.agents import evaluation

        self.assertEqual(
            evaluation.baseline_classify("fire and smoke everywhere")["incident_type"],
            "FIRE",
        )
