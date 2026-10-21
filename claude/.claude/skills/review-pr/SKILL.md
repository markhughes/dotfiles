---
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(git -C:*), Bash(git show:*), Bash(git cat-file:*), Read, Grep, Glob, Write, Edit
argument-hint: <PR URL or number>
description: Easier multi-agent review of a GitHub pull request, including useful nitpicks and test-reproduced bugs
---

Provide a code review of the pull request: $ARGUMENTS

PR metadata:
!`gh pr view $ARGUMENTS --json url,number,title,body,state,isDraft,author,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,files`

PR diff:
!`gh pr diff $ARGUMENTS`

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls. Make sure this is clear to every subagent that is launched.
- Only call a tool if it is required to complete the task. Every tool call should have a clear purpose.

**Reading files at the PR head (for any agent that needs context):**
- If a local clone exists at `~/src/github.com/<owner>/<repo>` and `git -C <clone> cat-file -e <headRefOid>` succeeds, use `git -C <clone> show <headRefOid>:<path>`.
- Otherwise use `gh api repos/<owner>/<repo>/contents/<path>?ref=<headRefOid> --jq .content | base64 -d`.
- Outside step 8, never check out, fetch, or modify the local clone.

To do this, follow these steps precisely:

1. Check preconditions (no subagent needed):
   - If no argument was given and `gh pr view` failed, stop and ask for a PR link.
   - If the PR is closed or merged, say so and stop.
   - If the diff is trivial and obviously correct (e.g. a typo fix, a version bump), state that and stop.

2. Launch a haiku agent to return a list of file paths (not their contents) for all relevant CLAUDE.md files at the PR head, including:
   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified by the PR

3. Write a one-paragraph summary of what the PR does, using its title, body and diff. This is passed to every subagent as context about the author's intent.

4. Fetch existing review comments once (`gh api repos/<owner>/<repo>/pulls/<number>/comments --jq '.[] | {path, line, body}'`). Pass them to every agent so already-raised points are not repeated.

5. Launch 6 agents in parallel to independently review the diff. Each agent receives the diff, the summary from step 3, the existing comments from step 4, and (where relevant) the CLAUDE.md paths from step 2. Each agent returns a list of issues, where each issue includes a description, the file and line(s) in the PR head, and the reason it was flagged (e.g. "CLAUDE.md adherence", "bug", "security", "nit").

   Agent 1: History sonnet agent
   Check whether the change undoes or repeats something the repo already learned.
   For each modified hunk, look at the recent history of those lines and files:
   - With a local clone: `git -C <clone> log -L <start>,<end>:<path> <headRefOid> -n 5`
     for each modified hunk, plus `git -C <clone> log --format='%h %s' -n 10 <baseRefName> -- <path>`
   - Without one: `gh api "repos/<owner>/<repo>/commits?path=<path>&sha=<baseRefName>&per_page=10"`
   Then fetch review comments from the last few merged PRs that touched the same
   files (`gh api "repos/<owner>/<repo>/commits/<sha>/pulls"` to find them).

   Flag only:
   - Lines that revert or undo a previous commit whose message describes a fix
     (cite the commit SHA and message)
   - Code that reintroduces a pattern a past reviewer asked to remove in these
     files (link the comment)
   - Removal of a guard, check, or workaround whose commit explains why it exists

   Do not flag: style changes, refactors that keep the earlier fix's behaviour,
   or anything where the history is ambiguous.

   Agent 2: Intent sonnet agent
   Compare what the PR says it does (title, body, linked issue if referenced via
   `gh api`) against what the diff actually does. Flag only:
   - Behaviour the description claims but the diff does not implement
     (e.g. "adds retry on timeout" with no retry logic)
   - User-visible behaviour changes the description does not mention: changed
     defaults, removed options, altered API responses, new error cases, changed
     config or migration behaviour
   - Code or tests left half-done in the diff that the description says are complete

   Each issue quotes the description claim (or notes its absence) and cites the
   diff lines. Do not flag missing detail in the description, wording, or scope
   choices the author explained.

   Agent 3: Opus bug agent (parallel with agent 4)
   Scan for obvious bugs. Focus only on the diff itself without reading extra context. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that you cannot validate without looking at context outside of the diff.

   Agent 4: Opus bug agent (parallel with agent 3)
   Look for problems in the introduced code: security issues, incorrect logic, broken edge cases, callers broken by a changed signature or behaviour. This agent MAY read files at the PR head to understand context, but must only flag issues that fall within the PR's changes.

   Agent 5: Sonnet nitpick agent
   Find nitpicks a thoughtful senior reviewer would actually leave a comment for. Each nit must make the code easier to read, safer to change, or more consistent with the codebase. Flag at most 5, ranked by usefulness. Good nits:
   - Names that mislead about what something does or holds
   - Comments or docstrings the change made stale or wrong
   - Dead code, unused parameters or unreachable branches introduced by the PR
   - New logic that duplicates an existing helper in the repo (cite it)
   - Deviations from a pattern used consistently in the surrounding code (cite an example)
   - Leftover debug output, commented-out code, or TODOs with no owner or ticket
   - Magic values that already have a named constant in the repo
   - Error messages or log lines that would not help someone debugging
   - Clear violations of a rule in a CLAUDE.md that governs the file (quote the rule and give the CLAUDE.md path). These don't count toward the 5-nit cap.
   Do NOT flag: formatting, import order, anything a linter or formatter catches, personal preference, "consider adding tests", or rewrites with no clear benefit.

   Agent 6: Test integrity sonnet agent
   Check whether the tests touched by the PR actually verify the change. This agent
   MAY read files at the PR head (the code under test, fixtures, helpers). Flag only:
   - Existing assertions changed to match new behaviour that the summary and
     description do not say was intended (the test was bent to fit the code)
   - Tests deleted, skipped, or marked xfail/only/focus without an explanation
     in the PR description
   - New tests that cannot fail: no assertions, asserting on a mock's own
     return value, or catching the exception they claim to test
   - Tests whose name or docstring claims to cover a case their body does not exercise
   - Test files the diff modifies that would no longer import or compile
     against the changed code

   Do not flag: missing tests, coverage gaps, test style, or fixture naming.

   **For agents 1–4 and 6, we only want HIGH SIGNAL issues.** Flag issues where:
   - The code will fail to compile or parse (syntax errors, type errors, missing imports, unresolved references)
   - The code will definitely produce wrong results regardless of inputs (clear logic errors)
   - A clear security defect is introduced (e.g. injection, secrets committed, auth check removed)
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken

   Do NOT flag:
   - Code style or quality concerns (agent 5 covers useful nits)
   - Potential issues that depend on specific inputs or state
   - Subjective suggestions or improvements

   If you are not certain an issue is real, do not flag it. False positives erode trust and waste the developer's time.

6. For each issue found in step 5 by agents 3, 4, 5, and 6, launch parallel subagents to validate the issue. These subagents get the summary from step 3 along with a description of the issue, and may read files at the PR head. The agent's job is to confirm with high confidence that the stated issue is truly an issue (e.g. if "variable is not defined" was flagged, verify that is actually true at the PR head). For CLAUDE.md issues, validate that the cited rule is scoped to this file and is actually violated. For nits, confirm the claim is true (the helper exists, the comment is stale, the pattern is consistent elsewhere) and that a senior reviewer would bother to raise it. Use Opus subagents for bugs, logic issues, and tests changed to match new behaviour; use sonnet subagents for CLAUDE.md violations, nits, and other test integrity issues.

7. Filter out any issues that were not validated in step 6, and any that duplicate an existing review comment. This gives the final list.

8. Reproduce confirmed bugs with a test.
   Only for issues in the final list that agents 3 or 4 flagged as a bug, logic error or
   security defect. Skip nits, CLAUDE.md, intent, history and test integrity issues.
   If there are none, skip this step.

   a. Find the repo. Use `~/src/github.com/<owner>/<repo>` if it exists. Otherwise ask
      the user for the local path and wait for the answer (subagents cannot ask, so do
      this before launching any). Confirm `git -C <path> remote -v` points at
      <owner>/<repo>, and note the remote name. If the user has no clone, skip this
      step and say so in the output.

   b. Put the PR code in a temporary worktree, so the user's checkout is never touched:
      - `git -C <clone> cat-file -e <headRefOid>`, and if that fails,
        `git -C <clone> fetch <remote> pull/<number>/head`
      - `git -C <clone> worktree add --detach <tmpdir> <headRefOid>`
      - Install dependencies in the worktree only if the test cannot run without them.
        If that needs anything beyond the repo's standard install command, ask first.

   c. For each issue, launch an Opus subagent, one at a time because they share the
      worktree. Each subagent:
      - Reads neighbouring tests first, then writes the smallest test that reproduces
        the bug, using the repo's existing framework, file layout and naming.
      - Runs only that test at the PR head. It must fail for the reason given in the
        issue, not because of an import error, missing fixture or setup problem.
      - Checks out the merge base
        (`git -C <tmpdir> checkout --detach $(git -C <clone> merge-base <headRefOid> <remote>/<baseRefName>)`)
        and runs the test again. It should pass there. If it also fails, the bug
        existed before the PR: drop the issue, per the false-positive list.
      - Checks out <headRefOid> again before finishing.
      - If the bug cannot reasonably be tested (it needs real credentials, network,
        timing or infrastructure), skips it and says why in one line. Do not force a test.
      - Returns the test file path, the test code, the exact command run, and at most
        10 lines of the failure output.

   d. If the test passes at the PR head after one corrected attempt, the bug was not
      reproduced. Keep the issue, move it to warning, and mark it "not reproduced by test".

   e. Remove the worktree with `git -C <clone> worktree remove --force <tmpdir>`.
      Never commit or push the tests.

9. Output the review to the terminal:
   - Start with the PR title and link.
   - If no issues were found, state: "No issues found. Checked for bugs, security defects, CLAUDE.md compliance, test integrity and useful nits." Then stop.
   - Otherwise list issues grouped by severity (blocker, warning, nit), each with:
     - File and line reference at the PR head, as a GitHub link (`<pr url>/files` is fine if a line link cannot be built)
     - A brief description and why it was flagged
     - A concrete suggested fix. For small, self-contained fixes, show the corrected code in a fenced block. For larger fixes (6+ lines, structural changes, or changes spanning multiple locations), describe the fix without a code block. Never show a "suggested fix" code block unless applying it fixes the issue entirely.
     - For issues tested in step 8: "Reproduced: fails at PR head, passes at base", the test code in a fenced block, the command to run it, and the trimmed failure output. For untestable or unreproduced issues, the one-line reason.

10. Do NOT post comments, approve, or request changes. If the user wants the findings posted, they will ask separately. The only writes allowed are the temporary worktree and test files from step 8, which are removed at the end. Never commit, push, or change the user's checked-out branch or working tree.

Use this list when evaluating issues in Steps 5, 6 and 8 (these are false positives, do NOT flag):

- Pre-existing issues in unchanged code
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns (e.g., lack of test coverage) unless explicitly required in CLAUDE.md
- Issues mentioned in CLAUDE.md but explicitly silenced in the code (e.g., via a lint ignore comment)
- Points already raised in existing review comments

Notes:

- Network access is limited to read-only `gh` calls for this PR's repo, plus `git fetch` of the PR and dependency installs in step 8. No web fetch.
- Create a todo list before starting.
- When citing a CLAUDE.md rule, quote the exact rule text and give the file path.
- The review target is the PR diff only. Other files may be read for context.
- Keep short and concise, 80% of the most critical info in 20% of the words. Use /humanizer and /crisp skills.
