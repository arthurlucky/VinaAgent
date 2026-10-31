---
name: research-report
description: Produce a sourced research brief on any topic. Use when the user asks for research, a comparison, a market or technology landscape, or a summary that needs citations.
---

# Research Report

Turn an open-ended question into a short, sourced brief the user can act on.

## Workflow

1. **Frame the question.** Write down the decision the user is trying to make
   and 2-4 sub-questions. If the request is ambiguous, ask one clarifying
   question before searching.
2. **Search broadly.** Run 3-6 `web_search` queries with different wording.
   Prefer primary sources (docs, filings, official blogs) over aggregators.
3. **Triage sources.** For each source note the publisher, date, and whether it
   is primary. Drop anything older than the user's time horizon unless it is
   historical context.
4. **Extract evidence.** Capture 1-3 verbatim facts per source with the URL.
   Never invent a number or a quote.
5. **Synthesise.** Group findings by sub-question. State where sources disagree
   instead of averaging them.
6. **Write the brief** using `references/report-template.md`.
7. **Save it.** Use `write_file` to store the brief as
   `research-<topic>-<date>.md` in the user's documents folder, then show the
   path.

## Rules

- Cite every non-obvious claim inline as `[source](url)`.
- Mark uncertainty explicitly: "not confirmed by a primary source".
- Keep the summary under 200 words; details go in the body.
- If fewer than two independent sources support a claim, say so.
