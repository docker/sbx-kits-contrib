"""Checks for the bundled deterministic tool fixture."""

from __future__ import annotations

import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


TOOLS = Path(__file__).parents[1] / "files/home/dapr-kit/example/tools.py"
fake_dapr_agents = types.ModuleType("dapr_agents")
fake_dapr_agents.tool = lambda function: function
SPEC = importlib.util.spec_from_file_location("dapr_kit_tools", TOOLS)
assert SPEC and SPEC.loader
tools = importlib.util.module_from_spec(SPEC)
with patch.dict(sys.modules, {"dapr_agents": fake_dapr_agents}):
    SPEC.loader.exec_module(tools)


class SampleWeatherTests(unittest.TestCase):
    def test_delay_is_bounded(self) -> None:
        with patch.dict(os.environ, {"DAPR_KIT_SAMPLE_DELAY_SECONDS": "45"}):
            with patch.object(tools.time, "sleep") as sleep:
                result = tools.sample_weather("Lisbon")
        sleep.assert_called_once_with(30)
        self.assertIn("Sample weather for Lisbon", result)

    def test_invalid_delay_falls_back_to_zero(self) -> None:
        with patch.dict(os.environ, {"DAPR_KIT_SAMPLE_DELAY_SECONDS": "not-a-number"}):
            with patch.object(tools.time, "sleep") as sleep:
                tools.sample_weather("Lisbon")
        sleep.assert_called_once_with(0)
