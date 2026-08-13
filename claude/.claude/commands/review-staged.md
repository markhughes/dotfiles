---
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git rev-parse:*), Read, Grep, Glob
description: Multi-agent review of staged changes before committing
---

Provide a code review of the currently staged changes (what would be included in the next commit).

Staged diff:
!`git diff --cached`

Staged file list:
!`git diff --cached --name-status`

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls. Make sure this is clear to every subagent that is launched.
- Only call a tool if it is required to complete the task. Every tool call should have a clear purpose.

To do this, follow these steps precisely:

1. Check preconditions (no subagent needed):
   - If the staged diff is empty, stop and tell the user nothing is staged (`git add` first).
   - If the staged changes are trivial and obviously correct (e.g. a typo fix in a comment, a version bump), state that and stop.

2. Launch a haiku agent to return a list of file paths (not their contents) for all relevant CLAUDE.md files including:
   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified by the staged changes

3. Write a one-paragraph summary of what the staged changes appear to do. This stands in for a PR title/description and will be passed to every subagent as context about the author's likely intent.

4. Launch 4 agents in parallel to independently review the staged diff. Each agent receives the staged diff, the summary from step 3, and (where relevant) the CLAUDE.md paths from step 2. Each agent returns a list of issues, where each issue includes a description, the file and line(s), and the reason it was flagged (e.g. "CLAUDE.md adherence", "bug", "security").

   Agents 1 + 2: CLAUDE.md compliance sonnet agents
   Audit staged changes for CLAUDE.md compliance in parallel. Note: When evaluating CLAUDE.md compliance for a file, only consider CLAUDE.md files that share a file path with the file or its parents.

   Agent 3: Opus bug agent (parallel with agent 4)
   Scan for obvious bugs. Focus only on the diff itself without reading extra context. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that you cannot validate without looking at context outside of the diff.

   Agent 4: Opus bug agent (parallel with agent 3)
   Look for problems that exist in the introduced code — security issues, incorrect logic, broken edge cases. This agent MAY read the surrounding unstaged file content and related files in the repo to understand context (e.g. how a modified function is called), but must only flag issues that fall within the staged changes themselves.

   **CRITICAL: We only want HIGH SIGNAL issues.** Flag issues where:
   - The code will fail to compile or parse (syntax errors, type errors, missing imports, unresolved references)
   - The code will definitely produce wrong results regardless of inputs (clear logic errors)
   - A clear security defect is introduced (e.g. injection, secrets committed, auth check removed)
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken
   - A partial staging hazard: the staged hunk references something that only exists in the unstaged working tree (e.g. a call to a function whose definition is not staged), so the commit would be broken on its own

   Do NOT flag:
   - Code style or quality concerns
   - Potential issues that depend on specific inputs or state
   - Subjective suggestions or improvements

   If you are not certain an issue is real, do not flag it. False positives erode trust and waste the developer's time.

5. For each issue found in step 4 by agents 3 and 4, launch parallel subagents to validate the issue. These subagents get the summary from step 3 along with a description of the issue, and may read the actual files in the repo to check. The agent's job is to confirm with high confidence that the stated issue is truly an issue (e.g. if "variable is not defined" was flagged, verify that is actually true in the code as staged). For CLAUDE.md issues, validate that the cited rule is scoped to this file and is actually violated. Use Opus subagents for bugs and logic issues, and sonnet agents for CLAUDE.md violations.

6. Filter out any issues that were not validated in step 5. This gives the final list of high-signal issues.

7. Output the review to the terminal:
   - If no issues were found, state: "No issues found in staged changes. Checked for bugs, security defects, partial-staging hazards, and CLAUDE.md compliance." Then stop.
   - If issues were found, list each issue with:
     - Severity (blocker / warning)
     - File and line reference into the staged version
     - A brief description and why it was flagged
     - A concrete suggested fix. For small, self-contained fixes, show the corrected code in a fenced block. For larger fixes (6+ lines, structural changes, or changes spanning multiple locations), describe the fix without a code block. Never show a "suggested fix" code block unless applying it fixes the issue entirely.

8. Do NOT modify any files or run any git commands that change state (no add, commit, checkout, restore, stash). This command is read-only.

   Exception: if the user invoked the command with the argument `--fix`, then after presenting the findings, apply the suggested fixes for validated blocker-level issues directly to the working tree using Edit, list exactly what was changed, and remind the user to re-stage (`git add`) and re-run /review-staged before committing. Never stage or commit on the user's behalf even with --fix.

Use this list when evaluating issues in Steps 4 and 5 (these are false positives, do NOT flag):

- Pre-existing issues in unchanged code
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns (e.g., lack of test coverage) unless explicitly required in CLAUDE.md
- Issues mentioned in CLAUDE.md but explicitly silenced in the code (e.g., via a lint ignore comment)
- Debug statements or TODOs, unless a CLAUDE.md rule explicitly forbids committing them

Notes:

- Everything is local. Never use gh, web fetch, or any network access.
- Create a todo list before starting.
- When citing a CLAUDE.md rule, quote the exact rule text and give the file path.
- The diff to review is always `git diff --cached` (the staged changes), never the working-tree diff. Unstaged content may be read for context but is not the review target.