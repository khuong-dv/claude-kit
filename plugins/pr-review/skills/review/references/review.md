# Code Review Rules

Default rule set for code review. Apply alongside the repo's CLAUDE.md (CLAUDE.md takes precedence on conflicts).

## 1. Correctness (highest priority)

- Obvious logic bugs: off-by-one, null/undefined access, race condition, deadlock, wrong boolean condition.
- Error handling: swallowed errors (empty catch, log-and-return-null), missing rollback when needed.
- Boundary conditions: empty input, single-element list, negative values, overflow, timezone issues.
- State machine: invalid state transitions, missing guards.

## 2. Requirement / ticket alignment

- Compare diff against ticket description. Is anything required but not implemented? Anything out of scope?
- Are acceptance criteria from the ticket covered by tests/code?
- Edge cases explicitly mentioned in the ticket — check specifically, don't speculate.

## 3. Security

- Unvalidated input going directly into SQL/shell/HTML.
- Hard-coded secrets (API keys, tokens, passwords).
- Auth/authz bypass: new routes missing middleware checks, missing ownership verification.
- User-supplied file paths — directory traversal.
- Logging/exposing sensitive data.

## 4. Performance (only flag when obvious)

- N+1 queries in loops.
- O(n²) on potentially large datasets (context shows n can be large).
- Memory leaks: subscriptions/listeners not cleaned up, file handles not closed.
- Blocking the event loop with sync I/O in async context.

Skip micro-optimizations without supporting data.

## 5. Readability & Maintainability

- Misleading variable/function names (`data`, `tmp`, `doStuff`).
- Functions > 50 lines doing multiple things — suggest splitting (only flag when genuinely hard to read).
- Magic numbers/strings repeated 3+ times without a constant.
- Stale comments contradicting the code.

## 6. Test coverage (only flag when serious)

- Complex new logic with zero tests.
- New tests that always pass regardless of code correctness (meaningless assertions, mocks returning expected results without exercising code).
- Bug fixes without regression tests.

Don't flag just because "tests are missing" — only flag when risk is high.

## 7. Backwards compatibility

- Public API/schema changes without migration or version bump.
- Database migrations that aren't reversible, or run long on large tables without batching.
- Breaking changes in shared libraries that consumers don't know about.

## 8. Do NOT flag (false positives)

- Stylistic preferences not in CLAUDE.md or this review.md.
- Issues a linter/typechecker/compiler would catch (CI will run them).
- Pre-existing issues on lines the PR didn't modify.
- Cosmetic refactors unrelated to bugs.
- Generic "should add tests" without identifying a specific risk.
- Suggesting a different library/framework.

## 9. Output format

Review comments must:

- Link to the exact code line (file:line, or GitHub permalink with full SHA).
- Classify as: `[blocker]` / `[suggestion]` / `[nit]`. Only blockers should block merge.
- Quote the specific rule from CLAUDE.md / review.md when applicable.
- Be concise. Avoid lengthy theoretical explanations.

## 10. Review priority

For large PRs, focus first on:
1. Newly added logic (new files or functions).
2. Changes in critical code paths (auth, payment, data persistence).
3. Migrations / schema changes.
4. Config / infrastructure changes.

Refactors and renames can be reviewed more quickly.
