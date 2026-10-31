---
name: code-review
description: Review Dart and Flutter code for correctness, lifecycle bugs, and style. Use when the user shares a diff, a file, or asks for a review before merging.
triggers: [review, kode, code, bug, refactor, periksa kode]
---

# Code Review

## Order of review

1. **Correctness** — logic, null safety, async gaps, error paths.
2. **Lifecycle** — `dispose`, stream subscriptions, `BuildContext` after
   `await`.
3. **State** — provider scope, rebuild loops, immutable updates.
4. **Performance** — rebuilds, list virtualization, image decoding, isolate
   offloading.
5. **Style** — naming, `const` usage, file layout matching the surrounding
   code.

## Checklist

- [ ] Every `await` is followed by a `mounted` / `context.mounted` check before
      using context.
- [ ] Controllers, timers and subscriptions are disposed.
- [ ] No `catch (_) {}` that hides a real failure without a comment.
- [ ] User-facing errors are actionable, not stack traces.
- [ ] New public APIs have doc comments.

## Output format

Group findings by severity:

```
BLOCKER  file:line — problem, why it matters, suggested fix
SHOULD   file:line — ...
NIT      file:line — ...
```

End with a one-line verdict: approve, approve with nits, or request changes.
