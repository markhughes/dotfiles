---
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(git -C:*), Bash(git show:*), Bash(git cat-file:*), Bash(mktemp:*), Read, Grep, Glob, Write, Edit
argument-hint: <PR URL or number>
description: Multi-agent review of a GitHub pull request with intent checks, impact tracing, evidence-backed findings, code suggestions and optional posting to GitHub
---

Provide a code review of the pull request: $ARGUMENTS

PR metadata:
!`gh pr view $ARGUMENTS --json url,number,title,body,state,isDraft,author,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,files`

PR diff:
!`gh pr diff $ARGUMENTS`

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls. Make sure this is clear to every subagent that is launched.
- Every tool call should have a clear purpose. Searching the repo to trace impact or gather evidence counts as a clear purpose.

**Reading files at the PR head (for any agent that needs context):**
- If a local clone exists at `~/src/github.com/<owner>/<repo>` and `git -C <clone> cat-file -e <headRefOid>` succeeds, use `git -C <clone> show <headRefOid>:<path>`, and search with Grep/Glob in the clone only if its checked-out tree matches the head (otherwise use `git -C <clone> grep <pattern> <headRefOid>`).
- Otherwise use `gh api repos/<owner>/<repo>/contents/<path>?ref=<headRefOid> --jq .content | base64 -d`, and `gh api "search/code?q=<symbol>+repo:<owner>/<repo>"` to find usages.
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

4. Fetch all existing discussion once and pass it to every agent, so already-raised points are not repeated:
   - Inline review comments: `gh api --paginate repos/<owner>/<repo>/pulls/<number>/comments --jq '.[] | {path, line, body, outdated: (.position == null)}'`
   - Review summaries: `gh api --paginate repos/<owner>/<repo>/pulls/<number>/reviews --jq '.[] | select(.body != "") | {state, body}'`
   - PR conversation: `gh api --paginate repos/<owner>/<repo>/issues/<number>/comments --jq '.[] | {body}'`
   A point counts as already raised only if the existing comment covers the same problem. If an earlier comment raised it and the code at the head still has the problem, the issue may be flagged again, noting the earlier comment.

5. Launch 6 agents in parallel to independently review the diff. Each agent receives the diff, the summary from step 3, the existing discussion from step 4, and (where relevant) the CLAUDE.md paths from step 2. Each agent returns a list of issues, where each issue includes a description, the file and line(s) in the PR head, the reason it was flagged (e.g. "CLAUDE.md adherence", "bug", "security", "intent", "history", "test integrity", "nit"), and any evidence it already gathered.

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

   Agent 4: Opus impact and bug agent (parallel with agent 3)
   Trace the impact of the change, then look for problems in the introduced code.
   - First, list every symbol whose signature, return value, thrown errors, side
     effects or meaning the PR changes: functions, methods, types, exported
     constants, config keys, environment variables, CLI flags, API routes,
     database columns, event names.
   - For each, search the repo at the PR head for every usage (callers, importers,
     overrides, implementations of a changed interface, serialised forms, docs and
     tests that depend on it). Read each call site the PR did not update and check
     it still works with the new behaviour.
   - Then look for security issues, incorrect logic and broken edge cases in the
     introduced code.
   May read any file at the PR head for context, but each flagged issue must be
   caused by the PR's changes. A broken caller outside the diff counts, because the
   PR broke it; cite both the changed line and the broken call site.

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
   - A caller or dependent the PR did not update will break
   - A clear security defect is introduced (e.g. injection, secrets committed, auth check removed)
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken

   Do NOT flag:
   - Code style or quality concerns (agent 5 covers useful nits)
   - Potential issues that depend on specific inputs or state that cannot be shown to occur
   - Subjective suggestions or improvements

   If you are not certain an issue is real, do not flag it. False positives erode trust and waste the developer's time.

6. For every issue found in step 5, by any agent, launch parallel subagents to validate it. These subagents get the summary from step 3 along with a description of the issue and any evidence the original agent gathered, and may read and search files at the PR head. The agent's job is to confirm with high confidence that the stated issue is truly an issue (e.g. if "variable is not defined" was flagged, verify that is actually true at the PR head; if a broken caller was flagged, read the caller and confirm it breaks). For history issues, confirm the cited commit or comment says what the issue claims. For intent issues, confirm the claim is in the description and the diff really does or doesn't implement it. For CLAUDE.md issues, validate that the cited rule is scoped to this file and is actually violated. For nits, confirm the claim is true (the helper exists, the comment is stale, the pattern is consistent elsewhere) and that a senior reviewer would bother to raise it. Use Opus subagents for bugs, logic issues, impact issues and tests changed to match new behaviour; use sonnet subagents for everything else.

   Each validator also states what evidence would convince a skeptical author, choosing from: "self-evident from the cited lines", "search result", "needs a test", or "cannot be proven locally" (with the reason).

7. Filter out any issues that were not validated in step 6, and any that duplicate an existing comment per step 4. This gives the final list.

8. Gather evidence for the final list.
   For each issue, gather the cheapest evidence that is conclusive, based on step 6:
   - Self-evident: cite the lines. No further work.
   - Search result: give the search command and the matching lines.
   - Needs a test: write one, following a–e below. A test can prove any issue type,
     not just bugs. For example, it can show that a test cannot fail (it still passes
     with the function body removed), that a claimed behaviour is missing, that a
     branch is unreachable, or that an unchanged caller now breaks.
   - Cannot be proven locally (needs real credentials, network, timing or
     infrastructure): say so in one line and rely on the reasoning.
   Do not write a test only to confirm what the cited lines already show.
   If no issue needs a test, skip a–e.

   a. Find the repo. Use `~/src/github.com/<owner>/<repo>` if it exists. Otherwise ask
      the user for the local path and wait for the answer (subagents cannot ask, so do
      this before launching any). Confirm `git -C <path> remote -v` points at
      <owner>/<repo>, and note the remote name. If the user has no clone, skip the
      tests, use the reasoning as evidence, and say so in the output.

   b. Put the PR code in a temporary worktree, so the user's checkout is never touched:
      - `git -C <clone> cat-file -e <headRefOid>`, and if that fails,
        `git -C <clone> fetch <remote> pull/<number>/head`
      - `git -C <clone> worktree add --detach <tmpdir> <headRefOid>`
      - Install dependencies in the worktree only if the test cannot run without them.
        If that needs anything beyond the repo's standard install command, ask first.

   c. For each issue that needs a test, launch an Opus subagent, one at a time because
      they share the worktree. Each subagent:
      - Reads neighbouring tests first, then writes the smallest test that proves the
        claim, using the repo's existing framework, file layout and naming.
      - Runs only that test at the PR head. For a bug, it must fail for the reason
        given in the issue, not because of an import error, missing fixture or setup
        problem. For another claim, the result must demonstrate the claim.
      - For bugs and regressions, checks out the merge base
        (`git -C <tmpdir> checkout --detach $(git -C <clone> merge-base <headRefOid> <remote>/<baseRefName>)`)
        and runs the test again. It should pass there. If it also fails, the bug
        existed before the PR: drop the issue, per the false-positive list. Skip the
        base comparison when it doesn't apply to the claim (e.g. a new test that
        cannot fail).
      - Checks out <headRefOid> again before finishing.
      - Returns the test file path, the test code, the exact command run, and at most
        10 lines of output.

   d. If the test does not prove the claim after one corrected attempt, keep the issue,
      move it to warning, and mark it "not proven by test", with the reasoning.

   e. Remove the worktree with `git -C <clone> worktree remove --force <tmpdir>`.
      Never commit or push the tests.

9. Output the review to the terminal:
   - Start with the PR title and link.
   - If no issues were found, state: "No issues found. Checked for bugs, impact on callers, security defects, intent, history, CLAUDE.md compliance, test integrity and useful nits." Then stop.
   - Otherwise list issues grouped by severity (blocker, warning, nit). Number every
     issue (#1, #2, …) across all groups so the user can pick which to post.
   - Each issue includes:
     - **Where:** file and line reference at the PR head, as a GitHub link
       (`<pr url>/files` is fine if a line link cannot be built). Say whether it can
       be anchored to a line in the diff; GitHub only accepts inline comments on
       lines the diff shows, so anything else goes in the summary body when posted.
     - **What:** the problem, in one or two sentences, and why it was flagged.
     - **When:** the inputs or conditions that trigger it, or "always". Skip for nits.
     - **Impact:** what breaks or goes wrong, and for whom. Skip for nits.
     - **Evidence:** the cited lines, the search command and result, or the test
       (code in a fenced block, the command, the trimmed output, and "Reproduced:
       fails at PR head, passes at base" where that applies). Name which kind of
       evidence it is. For unprovable or unproven issues, give the one-line reason.
     - **Fix:**
       - Small and self-contained: the corrected code in a fenced block. When posted,
         this becomes a GitHub `suggestion` block, so it must replace exactly the
         cited lines.
       - Larger or spanning several places: a code sketch in a fenced block labelled
         "Sketch", plus one sentence on what else needs to change.
       - Only label code as the fix if applying it fully fixes the issue.
   - Write so the author can act without redoing the investigation.

10. Ask before posting. After printing the review, ask:
    "Post to GitHub? Reply `all`, a list of issue numbers (e.g. `1,3,5`), edits
    (e.g. `drop 2`, `make 4 a nit`), or `no`." Then wait for the reply.
    If the user says `no`, stop. Never approve or request changes unless the user
    explicitly asks. Never commit, push, or change the user's checked-out branch or
    working tree.

11. Post the review (only after the user says which issues to post).

    a. Re-check the head: `gh pr view <number> --json headRefOid`. If it differs from
       the reviewed <headRefOid>, tell the user that new commits landed and ask whether
       to post anyway, because line anchors may be stale.

    b. Create a temp file with `mktemp`, build one review in it, and post it in a
       single call, so all comments arrive together:
       `gh api repos/<owner>/<repo>/pulls/<number>/reviews -X POST --input <tmpfile>`

       ```json
       {
         "commit_id": "<headRefOid>",
         "event": "COMMENT",
         "body": "<summary body, format below>",
         "comments": [
           { "path": "src/x.ts", "line": 42, "side": "RIGHT", "body": "<inline body>" },
           { "path": "src/y.ts", "start_line": 10, "line": 14, "start_side": "RIGHT",
             "side": "RIGHT", "body": "<inline body>" }
         ]
       }
       ```
       Use `event: "COMMENT"` unless the user explicitly asks for `REQUEST_CHANGES` or `APPROVE`.

    c. Inline comment format (one per anchorable issue):

       ````
       **<blocker|warning|nit>: <short title>**

       <What: 1–2 sentences.> <When it triggers.> <Impact.>

       ```suggestion
       <replacement for exactly the commented line range>
       ```

       <details><summary>Evidence: <reproduced by test | search | reasoning></summary>

       ```<lang>
       <test code, or search command and matches>
       ```
       `<command>`
       ```
       <trimmed output>
       ```
       </details>
       ````
       - Use a `suggestion` block only when it replaces exactly lines `start_line`–`line`
         and fully fixes the issue. Otherwise use a plain fenced block labelled "Sketch".
       - Keep self-evident evidence inline (a sentence citing the lines) rather than in
         a `<details>` block.
       - For CLAUDE.md issues, quote the rule and give the CLAUDE.md path.
       - Omit "When" and "Impact" for nits.

    d. Summary body format:

       ```
       **Automated review**: <N> blockers, <N> warnings, <N> nits (details inline).

       <One sentence on the overall state, e.g. "One reproduced bug in retry handling
       blocks merge; the rest are minor.">

       **Not tied to a diff line**
       - **<severity>: <title>**: <what, when, impact>. Evidence: <…>. Fix: <…>
         (<file, call site or commit link>)

       Checked: bugs, impact on callers, security, intent vs description, history,
       CLAUDE.md, test integrity.
       ```
       Drop the "Not tied to a diff line" section if it's empty. Intent, history and
       broken-caller findings outside the diff usually land there.

    e. If the API rejects a comment (usually a line outside the diff), move that issue
       into the summary body and retry once. Report the review URL from the response,
       then delete the temp file.

Use this list when evaluating issues in Steps 5, 6 and 8 (these are false positives, do NOT flag):

- Pre-existing issues in unchanged code that the PR does not make worse
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns (e.g., lack of test coverage) unless explicitly required in CLAUDE.md
- Issues mentioned in CLAUDE.md but explicitly silenced in the code (e.g., via a lint ignore comment)
- Points already raised in existing discussion and still covered there (see step 4)

Notes:

- Network access is limited to `gh` calls for this PR's repo (read-only until step 11, which posts one review), plus `git fetch` of the PR and dependency installs in step 8. No web fetch.
- Create a todo list before starting.
- When citing a CLAUDE.md rule, quote the exact rule text and give the file path.
- The review target is the PR's changes and anything they break. Other files may be read and searched for context.
- Be concise: no preamble, no restating the diff, no hedging. But completeness of each issue (what, when, impact, evidence, fix) takes priority over brevity. Use /humanizer for tone. 