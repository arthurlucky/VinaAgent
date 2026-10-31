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
| `search_skill_marketplace` | Search public GitHub skill repositories |
| `install_marketplace_skill` | Download and install a marketplace skill |

## Skill marketplace

`Settings > Agent Skills > storefront icon` opens the marketplace.

The catalog is read directly from the public GitHub repositories that power
skills.sh and ClawHub (`npx skills add owner/repo`), so no API key is needed:

- `anthropics/skills` — official Agent Skills examples
- `vercel-labs/skills` — find-skills and web workflows
- `obra/superpowers` — brainstorming, TDD, debugging, planning
- `mattpocock/skills` — TypeScript, code review, refactoring
- `microsoft/azure-skills` — Azure diagnostics, cost, RBAC
- `supabase/agent-skills`, `prisma/skills`, `remotion-dev/skills`,
  `emilkowalski/skills`

How it works:

1. `GET /repos/{owner}/{repo}` resolves the default branch.
2. `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1` lists every
   `SKILL.md` in the repository, whatever the folder layout.
3. `raw.githubusercontent.com` downloads the skill folder (text files only,
   max 40 files / 4 MB per skill).
4. `SkillStore.installSkill` writes the files under
   `<app documents>/skills/<name>/` plus a `.marketplace` metadata marker.

Users can add any `owner/repo` from the marketplace screen; the list is stored
in `SharedPreferences` under `marketplace_custom_sources`.

### Why not the marketplace APIs directly?

- **skills.sh** requires a Vercel OIDC bearer token (`401` otherwise), which a
  mobile app cannot mint.
- **ClawHub** has no stable public REST API yet.

Both index the same GitHub repositories, so installing from the upstream repo
gives the same skills with no key and no proxy.

## Auto-activation

Skills must work even in plain chat mode, where the model cannot call tools.
Before every request `ChatController._buildHistory` scores installed skills
against the latest user message:

- skill name tokens → +4
- description tokens → +1
- whole-word name tokens → +3
- `triggers` from the frontmatter → +6

The top two skills with a score of at least 4 are injected into the system
prompt as `## Active skill: <name>` with their full `SKILL.md` body (truncated
to 5000 chars, 1800 for local models). A skill can also be forced for one
message with `/skill <name> <prompt>`.

```markdown
---
name: research-report
description: Produce a sourced research brief.
triggers: [riset, laporan, research, report, analisis]
---
```

`triggers` are optional, any language, and are stripped to lowercase words.

## Slash commands

The composer recognises `/` commands. Type `/` to open the suggestion list.

| Command | Action |
| --- | --- |
| `/help` | Show every command |
| `/skills` | Browse installed skills |
| `/skill <name> [prompt]` | Force a skill for the next message |
| `/marketplace` | Open the skill marketplace |
| `/agent` | Switch to Agent mode |
| `/chat` | Switch to plain Chat mode |
| `/local` | Switch to an on-device model |
| `/new` | Start a new conversation |
| `/model` | Open model settings |
| `/mcp` | Open MCP settings |
| `/image <prompt>` | Generate an image (alias `/img`) |

`/skill <name>` without a prompt pins the skill to the composer as a chip and
applies it to the next message.

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
