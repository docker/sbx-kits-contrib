# Copyright 2026 The Dapr Authors
# SPDX-License-Identifier: Apache-2.0
#
# Adapted from dapr/dapr-agents quickstarts/03_durable_agent_http.py at
# 98b75469f4d9b0d9a091ece90bd05f88e5b03ba8. Kit-specific changes are limited
# to names and the deterministic local weather tool.
from dapr_agents import AgentRunner, DurableAgent
from dapr_agents.agents.configs import AgentMemoryConfig, AgentStateConfig
from dapr_agents.llm import DaprChatClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.storage.daprstores.stateservice import StateStoreService

from tools import sample_weather


def main() -> None:
    agent = DurableAgent(
        name="SandboxWeatherAgent",
        role="Weather assistant",
        instructions=[
            "Answer weather questions with the sample_weather tool.",
            "Always call sample_weather before answering a weather question.",
        ],
        tools=[sample_weather],
        llm=DaprChatClient(component_name="llm-provider"),
        memory=AgentMemoryConfig(
            store=ConversationDaprStateMemory(store_name="agent-memory"),
        ),
        state=AgentStateConfig(
            store=StateStoreService(store_name="agent-workflow"),
        ),
    )
    runner = AgentRunner()
    try:
        runner.serve(agent, port=8001)
    finally:
        runner.shutdown()


if __name__ == "__main__":
    main()
