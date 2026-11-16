# Copyright 2026 The Dapr Agents Sandbox Kit Authors
# SPDX-License-Identifier: Apache-2.0
import os
import time

from dapr_agents import tool


@tool
def sample_weather(city: str) -> str:
    """Return deterministic sample weather data for a requested city."""
    try:
        delay = float(os.environ.get("DAPR_KIT_SAMPLE_DELAY_SECONDS", "0"))
    except ValueError:
        delay = 0
    time.sleep(min(max(delay, 0), 30))
    normalized = city.strip() or "the requested location"
    return f"Sample weather for {normalized}: clear skies, 21°C (70°F), light wind."
