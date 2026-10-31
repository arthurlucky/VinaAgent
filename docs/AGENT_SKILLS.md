# Agent Skills

PocketStrike ships a progressive-disclosure skill system modelled on
[Anthropic Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview).

A skill is a folder containing a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: research-report
description: Produce a sourced research brief. Use when the user asks for research or a comparison.
---

# Research Report

1. Frame the question.
2. Search 3-6 queries.
```

## Progressive disclosure

| Level | Content | When it enters context |
| --- | --- | --- |
| 1 | `name` + `description` | Always, in the system prompt |
| 2 | `SKILL.md` body | When the model calls `load_skill` |
| 3 | `references/*` files | When the model calls `read_skill_resource` |

Only metadata is paid for up front, so dozens of skills can be installed
without bloating the prompt.

## Storage

```
<app documents>/skills/<name>/SKILL.md
<app documents>/skills/<name>/references/...
```

Bundled skills live in `assets/skills/` and are copied to the device on first
run. The copy is skipped when the target file already exists, so user edits are
never overwritten.

## Agent tools

| Tool | Purpose |
| --- | --- |
| `list_skills` | List installed skills and their state |
| `load_skill` | Load the full instructions for one skill |
| `read_skill_resource` | Read a bundled reference file |
| `create_skill` | Persist a new skill created by the agent |

## Settings UI

`Settings > Agent Skills` lists every installed skill, shows its body, lets the
user enable or disable individual skills, delete custom ones, and create new
skills manually.

## Bundled skills

- `research-report` — sourced research briefs (with a report template)
- `android-automation` — safe multi-step phone automation
- `image-prompting` — prompts for the image generation tool
- `code-review` — Dart/Flutter review checklist
- `skill-authoring` — how the agent writes new skills
