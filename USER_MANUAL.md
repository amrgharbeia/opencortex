# OpenCortex v0.1.0 User Manual

OpenCortex is a neurosymbolic AI agent designed for autonomous Memex maintenance. It combines the probabilistic power of Large Language Models with the deterministic safety of Common Lisp and the structured clarity of Org-mode.

## 1. Quick Start

Install and boot OpenCortex with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/gharbeia/opencortex/main/opencortex.sh | bash
```

Once installed, simply run `opencortex` to start the interactive CLI.

## 2. The Core MVP Skills

The v0.1.0 release includes the following essential skills:

### Safety & Integrity
*   **System Policy:** Enforces core invariants (Sovereignty, Transparency).
*   **The Bouncer:** Inspects all proposed actions and blocks high-risk operations.
*   **Protocol Validator:** Ensures communication integrity.

### Cognitive Kernel
*   **LLM Gateway:** Routes requests to your preferred provider (Gemini, Anthropic, etc.).
*   **Peripheral Vision:** Manages context and retrieves relevant notes via Sparse Trees.
*   **Memory Steward:** Maintains the live graph of your Org-mode Memex.
*   **Credentials Vault:** Securely stores your API keys.

### Interaction & Actuation
*   **CLI Gateway:** The primary interface for chatting with your agent.
*   **Shell Actuator:** Allows the agent to perform safe system side-effects.

### Autonomous Services
*   **The Scribe:** Automatically distills your daily chronological logs into structured notes.
*   **The Gardener:** Proactively repairs broken links and flags orphaned nodes.

## 3. Basic Usage

### Chatting
Type natural language messages into the CLI. The agent will perceive your intent, consult its Memory, and propose actions.

### Memex Maintenance
OpenCortex monitors your `daily/` directory. Use the Scribe to distill your thoughts:
`User: Distill my notes from yesterday.`

### Safety Approvals
When the Bouncer intercepts a high-impact action, it will create a "Flight Plan" in your Memex. You must mark it as `APPROVED` before the agent proceeds.

## 4. Configuration

All configuration is stored in the `.env` file in your installation directory. You can update your API keys, change your Assistant's name, or modify the mandatory skill list there.

---
*OpenCortex: The Conductor of your Life Stack.*
