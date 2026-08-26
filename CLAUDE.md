# CLAUDE.md

The `newrelic_rpm` gem: instruments customer Ruby apps and reports performance data to New Relic.

## Hard rule: local work only

Everything stays on this machine, in the working tree. An engineer reviews the changes and takes
every outward-facing action themselves. Never do these, never offer to, never propose them as a next
step: git writes (`commit`, `add`/staging, `push`, `amend`, `rebase`, `reset --hard`, `tag`, `stash`)
or anything that leaves this machine (opening, updating, commenting on, or merging PRs and issues).

## Constraints

This gem loads into other people's production apps:

- **Zero runtime dependencies.** The main agent requires no gems.
- **Ruby >= 2.6** (`newrelic_rpm.gemspec`). No newer syntax — and RuboCop targets 2.7, so a clean
  `rubocop` run does not prove 2.6 compatibility.
- **Plain Ruby only** — no `ActiveSupport`/`ActiveRecord` idioms (`blank?`, `present?`, `try`).
  We can't assume any library is loaded.

# Comment discipline

Default to no comments. Only add one when the WHY is genuinely non-obvious from the code
itself — a hidden constraint, a subtle invariant, a workaround for something specific, or
behavior that would surprise a reader. Never comment on WHAT the code does; well-named
identifiers already say that. When a comment is warranted, keep it to one or two lines.

Don't reference PR numbers, issue numbers, task history, or "this was added for X" in
comments — that belongs in the commit message or PR description, not the code.

## Testing

Every change needs tests, in the suite that matches it:

| Change | Suite | Command |
| --- | --- | --- |
| Core agent logic | unit — `test/new_relic/` | `TEST=<file> bundle exec rake test`, narrow with `TESTOPTS="--name=test_x"` |
| Gem instrumentation | multiverse — `test/multiverse/suites/<name>/` | `run_tests -q <name>` (one env, fast loop), `-m <name>` (full) |
| Rails-version-specific | env — `test/environments/` | `run_tests -e 72,80` (comma-separated, leading `rails` optional) |

`./test/script/run_tests -h` lists every flag. Run the tests covering the code you changed plus its
callers — `grep` the changed method or class name to find them. Details: `test/README.md`,
`test/multiverse/README.md`.

## Before you say you're done

1. `bundle exec rubocop` is clean on changed files. Fix the code — don't regenerate
   `.rubocop_todo.yml` to make new offenses disappear.
2. The tests above pass.
3. `CHANGELOG.md` entry for any user-facing change, under a `## dev` heading at the top of the file
   (create it if the last release closed it out), matching the format of the entries below.
