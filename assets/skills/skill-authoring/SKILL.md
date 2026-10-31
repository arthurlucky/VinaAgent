---
name: skill-authoring
description: Create or improve reusable agent skills. Use when the user asks to save a workflow, teach the agent a procedure, or when a repeated task deserves its own skill.
---

# Skill Authoring

A skill is a folder with a `SKILL.md` file. Skills use progressive disclosure,
so only the name and description cost context until the skill is loaded.

## Anatomy

```markdown
---
name: kebab-case-name
description: What it does. Use when <trigger conditions>.
---

# Title

## Workflow

1. ...
```

## Rules

- `name`: lowercase letters, numbers and hyphens, max 64 characters.
- `description`: max 1024 characters and must include **when** to use the skill,
  not just what it does.
- Body: step-by-step instructions, under about 500 lines. Move long references
  to sibling files and link them.
- Reference files: `references/*.md`, templates, checklists. Read them only when
  needed.
- Never put secrets or personal data in a skill.

## How to create one

1. Ask the user for the trigger and the desired outcome.
2. Draft the body with numbered steps and explicit stop conditions.
3. Call `create_skill` with name, description and instructions.
4. Tell the user the skill is available and how to disable it in
   Settings > Agent Skills.
