# Codex — Project instructions

Codex turns one brand's design system into reusable specifications and generated advertising
creative. This repository is the reusable starter, not a brand's production project.

## Load the Codex rules first

OpenCode loads this `AGENTS.md` but does not automatically load `CLAUDE.md`. Before the first
project task, read `CLAUDE.md` and `RULES.md`, then read every `.claude/knowledge/` file listed in
the **Knowledge — load first** section of `CLAUDE.md`. Treat those files as the source of truth for
Codex's structure, workflow, terminology, and constraints.

At the start of each brand-project session, load the `codex-workflow` skill and determine whether
the work is in Setup or Execution. Re-evaluate the stage when the user brings new material or a
request that exposes an undocumented gap.

## Operating rules

- Speak with the user in clear, plain Spanish. Keep project artifacts in English unless the user
  explicitly asks otherwise.
- Do not invent brand values, copy, geometry, or behavior. Ask about gaps; ask one question at a
  time.
- Do not enter Execution while relevant Setup gaps remain or before the required validation piece
  is approved.
- Build one framework at a time. When asked for Figma anatomy, the HTML anatomy template is the
  deliverable for that task; it is not the final campaign creative.
- For a request to generate a framework's anatomy from a selected Figma frame, load
  `codex-figma-anatomy` and follow its Figma MCP procedure. Do not implement the final campaign
  piece or modify the Figma file as part of that task.
- Treat `CLAUDE.md`, `RULES.md`, and `.claude/` as the harness during brand-project work. Do not
  change them from a brand task. Changes to this starter's harness are maintainer work and require
  an explicit user request.

## Skill discovery

OpenCode discovers the project's `.claude/skills/` directory as a compatibility source. Load skills
by their directory ID when the task matches; their `SKILL.md` files are the source of truth for
task-specific procedures.
