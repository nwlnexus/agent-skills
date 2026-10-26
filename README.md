# agent-skills

Reusable, repo-agnostic skills for coding agents (Claude Code `SKILL.md` format; also readable by
anything that follows the [Agent Skills](https://agentskills.io) layout). Each skill is a procedure
that was worked out once in a real repo and generalised so it can be applied the same way anywhere.

It also holds the **session harness** every Claude session on the owner's hosts runs with: the
`long-task` skill, the `claim-verifier` agent, the session-contract fragment for the global
`CLAUDE.md`, and the progress-file template (design: `nwlnexus/olympus-sdk`
`docs/superpowers/specs/2026-10-26-agent-harness-knowledge-and-hosts-design.md`, decisions H1 to H5).

## Skills

| Skill | Use it when |
| --- | --- |
| [`gitnexus-no-churn`](skills/gitnexus-no-churn/SKILL.md) | Setting up or repairing [GitNexus](https://github.com/abhigyanpatwari/GitNexus) in a repo so it never reports "index N commits behind" after commits and never rewrites `CLAUDE.md`/`AGENTS.md`. Hooks keep the index at HEAD with `--index-only`; docs are generated once with `--no-stats`. |
| [`long-task`](skills/long-task/SKILL.md) | A task expected to take more than about 30 minutes, or any issue with a "Done when". Registers the session in memory, keeps `docs/progress/<date>-<issue>-<slug>.md` on the branch (removed before merge), turns the Done-when into a `/goal`, delegates by tier, and calls `claim-verifier` before any "done", `gh pr ready` and merge. Planning runs at `effort: high`. |

## Agents

| Agent | Model / effort | Use it when |
| --- | --- | --- |
| [`claim-verifier`](agents/claim-verifier.md) | sonnet / medium, `memory: project` | Before reporting a claim as done, readying a PR or merging. Re-runs every Done-when check from the progress file, confirms every cited URL, issue, `file:line` and commit, returns PASS or FAIL with evidence. Read-only. |

## Fragments and templates

| File | What it is |
| --- | --- |
| [`fragments/session-contract.md`](fragments/session-contract.md) | The session contract (progress file, goal, verify-before-done, effort, registry, parallelism, naming, cross-session messages). Nix appends its body, without the frontmatter, to each Claude dir's global `CLAUDE.md` between managed markers. |
| [`templates/progress.md`](templates/progress.md) | The progress-file template `long-task` copies (`skills/long-task/progress-template.md` links to it). Sections: Goal, Done-when checks, Plan, Evidence log, Decisions, Blocked-on, Next. |

## Layout

```text
skills/<name>/SKILL.md        # frontmatter: name, description (the trigger) + the procedure
skills/<name>/scripts/…       # anything the procedure copies into a target repo
agents/<name>.md              # Claude Code subagent: frontmatter (name, description, tools, model, effort, memory) + system prompt
fragments/<name>.md           # text appended to a managed file; frontmatter (name, description, target) is stripped
templates/<name>.md           # files a skill copies into a target repo
```

A skill directory is self-contained: `SKILL.md` plus whatever files it tells the agent to install
(a relative symlink to `templates/` is allowed; the validator checks it resolves inside the repo).
Nothing here runs on its own.

## Installing

Claude Code loads skills from `~/.claude/skills/<name>/` (user scope) or `.claude/skills/<name>/`
(project scope). Either symlink or copy a skill directory there:

```sh
git clone https://github.com/nwlnexus/agent-skills ~/src/agent-skills
ln -s ~/src/agent-skills/skills/gitnexus-no-churn ~/.claude/skills/gitnexus-no-churn
```

Agents go in `~/.claude/agents/<name>.md` (user scope) or `.claude/agents/` (project scope). The
contract fragment is plain Markdown after its frontmatter; append that part to `~/.claude/CLAUDE.md`.

Nix users: consume the repo as a non-flake input and point `home.file` at `skills/<name>` and
`agents/<name>.md` (this is how [`nwlnexus/nix-darwin-hm`](https://github.com/nwlnexus/nix-darwin-hm)
installs them into every Claude config dir; it also keeps the fragment in a marked block of each
dir's `CLAUDE.md`).

## Contributing a skill

1. `skills/<kebab-name>/SKILL.md` with `name` (= directory name) and a `description` that states
   *when* to use it — that line is what triggers the skill, so lead with the situations.
2. Keep the body a procedure: preconditions, steps, verification, rules of thumb. Generalise
   (detect the repo's hook manager / package manager / doc files; don't hardcode one stack).
3. Scripts the skill installs go under `scripts/` and must pass `shellcheck`.
4. Agents: `agents/<name>.md` with `name` (= file name, no `:`), a `description` that says when to
   delegate, and explicit `model` and `effort`. Fragments: frontmatter `name`, `description`,
   `target`; the body starts with a level-2 heading.
5. `scripts/validate-skills.sh` runs in CI and locally (frontmatter must parse as YAML: quote a
   description that contains a colon followed by a space, or a space followed by `#`).

## License

MIT — see [LICENSE](LICENSE).
