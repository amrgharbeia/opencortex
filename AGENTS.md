# OpenCortex Agent Mandate

This file defines the operating policies and engineering guidelines that all autonomous agents MUST follow.

## Vision

- **Pure Lisp + Org-mode**: All intelligence implemented in Lisp, all documentation in Org-mode
- **No JSON, No YAML**: Thin harness, fat skills
- **Constraint**: No temporary scripts in repo - use `/home/user/memex/system/` instead

## Current Goal

- **v0.2.0**: Self-Improvement + Local LLMs
  - org-skill-self-edit (self-modification)
  - org-skill-emacs-edit (full org-mode manipulation)
  - Local vector search (Ollama embeddings)
  - Tool permission tiers (ask/allow/deny)
  - Skill hot-reload ✅ DONE

## Engineering Standards

### Mandates (Operational)

1. **Commit Before Modify**: MUST commit and push workspace BEFORE initiating any file modifications. Working tree MUST be clean before modification.

2. **Literate Programming**: All system logic and skills MUST be implemented as Literate Org files. The "Why" (Architectural Intent) MUST NOT be separated from the "How" (Implementation).

3. **Test-Driven Development**: No change is complete without verification. Every new function or macro MUST have a FiveAM test case.

4. **The Consensus Loop (Plan Mode)**: Major architectural shifts require a formal implementation plan. Must draft Blueprint (PROTOCOL) and seek formal approval before execution.

5. **GTD Synchronization**: Every task completion MUST update `gtd.org`. Record all major architectural shifts, feature implementations, or refactors in the project roadmap.

6. **Test-First Methodology**: Before implementing any fix or feature:
   - Design the test/success criteria first - define what "works" means
   - Run chaos/edge-case testing - try to break the design
   - Only then implement the solution

7. **Org as Thinking Medium**: When debugging or analyzing issues, document investigation in the relevant org file BEFORE implementing a fix. Record root cause hypothesis, evidence found, tradeoffs considered.

8. **Engineering Decision Audit Trail**: Every significant fix or architectural decision MUST be documented with:
   - Root cause analysis
   - Options considered and tradeoffs
   - Why this solution was chosen

### Agent Workflow

- **Boot Sequence**: Read AGENTS.md, verify git status, read gtd.org for current task
- **Before Any Modification**: Commit first (Commit Before Modify rule)
- **Plan Mode**: Draft PROTOCOL.md before complex implementations
- **Testing**: Run FiveAM test suite before marking task complete
- **Completion**: Update gtd.org, commit, sync with user

## References

- Engineering Standards: `../opencortex-contrib/skills/org-skill-engineering-standards.org`
- Roadmap: `gtd.org`
- README: `README.org`