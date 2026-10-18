# agent-skills

Reusable, repo-agnostic skills for coding agents (Claude Code `SKILL.md` format; also readable by
anything that follows the [Agent Skills](https://agentskills.io) layout). Each skill is a procedure
that was worked out once in a real repo and generalised so it can be applied the same way anywhere.

## Skills

| Skill | Use it when |
| --- | --- |
| [`gitnexus-no-churn`](skills/gitnexus-no-churn/SKILL.md) | Setting up or repairing [GitNexus](https://github.com/abhigyanpatwari/GitNexus) in a repo so it never reports "index N commits behind" after commits and never rewrites `CLAUDE.md`/`AGENTS.md`. Hooks keep the index at HEAD with `--index-only`; docs are generated once with `--no-stats`. |

## Layout

```text
skills/<name>/SKILL.md        # frontmatter: name, description (the trigger) + the procedure
skills/<name>/scripts/…       # anything the procedure copies into a target repo
```

A skill directory is self-contained: `SKILL.md` plus whatever files it tells the agent to install.
Nothing here runs on its own.

## Installing

Claude Code loads skills from `~/.claude/skills/<name>/` (user scope) or `.claude/skills/<name>/`
(project scope). Either symlink or copy a skill directory there:

```sh
git clone https://github.com/nwlnexus/agent-skills ~/src/agent-skills
ln -s ~/src/agent-skills/skills/gitnexus-no-churn ~/.claude/skills/gitnexus-no-churn
```

Nix users: consume the repo as a non-flake input and point `home.file` at `skills/<name>`
(this is how [`nwlnexus/nix-darwin-hm`](https://github.com/nwlnexus/nix-darwin-hm) installs them
into every Claude config dir).

## Contributing a skill

1. `skills/<kebab-name>/SKILL.md` with `name` (= directory name) and a `description` that states
   *when* to use it — that line is what triggers the skill, so lead with the situations.
2. Keep the body a procedure: preconditions, steps, verification, rules of thumb. Generalise
   (detect the repo's hook manager / package manager / doc files; don't hardcode one stack).
3. Scripts the skill installs go under `scripts/` and must pass `shellcheck`.
4. `scripts/validate-skills.sh` runs in CI and locally.

## License

MIT — see [LICENSE](LICENSE).
