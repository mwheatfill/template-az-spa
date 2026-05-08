# `agent/` — Microsoft 365 Copilot agent

Empty by default. Populate this folder when the app gains a Microsoft 365 Copilot agent
(declarative agent + API plugin + Adaptive Card response templates).

## Install

Use the [`+copilot-agent` recipe](https://github.com/mwheatfill/app-platform-recipes/tree/main/recipes/%2Bcopilot-agent):

```bash
# from the repo root
curl -sSL https://raw.githubusercontent.com/mwheatfill/app-platform-recipes/main/install.sh | \
  bash -s -- +copilot-agent
```

The recipe scaffolds:

- `agent/declarativeAgent.json` — agent identity, instructions, scope
- `agent/plugin.json` — API plugin manifest pointing at `/api/openapi.json`
- `agent/adaptiveCards/` — response templates
- `agent/manifest.json` — Teams app manifest for sideload / catalog

## Why an empty folder

It signals intent. Apps in this template family are expected to grow agent surfaces over time;
having the folder pre-named keeps that path visible without forcing every app to populate it.

## Convention

The agent **wraps the existing OpenAPI spec** at `/api/openapi.json`. Don't reimplement
endpoint logic in the agent layer — derive from the contract. If the agent needs to call
endpoints without an EasyAuth session (typical for app-only Copilot scenarios), see the
"Per-route auth" section in [AGENTS.md](../AGENTS.md).
