# Fleet Control agent config schema

Generates the JSON Schema (Draft 2020-12) that Fleet Control uses to validate and
render Ruby agent configuration. The schema is derived from the agent's own
`NewRelic::Agent::Configuration::DEFAULTS`, so there's no separate list to keep in sync.

## Files

| File | Purpose |
|------|---------|
| `generate_schema.rb` | Builds `../schemas/config.json` from `DEFAULTS`. |
| `schema_diff.rb` | Classifies changes between two schemas and recommends a version bump. |
| `bump_schema_version.rb` | Bumps the schema version in `../configurationDefinitions.yml` from the diff since the last release. |
| `tests/` | Minitest suites for each of the above. |

Output: `../schemas/config.json`. Version + schema path live in `../configurationDefinitions.yml`.

## Commands

```bash
# regenerate the schema (writes only if it changed)
ruby generate_schema.rb                 # or: bundle exec rake newrelic:config:schema

# preview / apply a version bump
ruby bump_schema_version.rb             # dry-run: report the recommended bump
ruby bump_schema_version.rb --write     # apply it

# tests
ruby tests/generate_schema_test.rb
ruby tests/schema_diff_test.rb
ruby tests/bump_schema_version_test.rb
```

`generate_schema.rb` exit codes: `0` unchanged, `1` changed, `2` failure. It validates
its output against the Draft 2020-12 meta-schema when `json_schemer` is installed.

## How versioning works

- **On push** (`.github/workflows/agent_config_schema.yml`): regenerates `config.json`
  and commits it if it changed.
- **At prerelease** (`prerelease.yml`): diffs the current schema against the previous
  release's, bumps the version in `configurationDefinitions.yml`, and includes it in the
  prerelease PR. No previous schema → treated as the first release, no bump.

## Version bump rules

| Change | Bump |
|--------|------|
| Property removed · type changed · enum introduced · enum value removed | major |
| Property added · enum value added · enum removed · default changed | minor |
| Description changed | patch |

The highest-severity change present wins.

## Notes

- The schema uses **flat dotted keys** (`transaction_tracer.enabled`) and public,
  non-deprecated settings only.
- `additionalProperties: true` is intentional: a deployment may validate against an older
  schema, and newer keys shouldn't be rejected.
- Enum values that aren't in a setting's `:allowlist` come from override maps in
  `generate_schema.rb`; the diff rules for `required` are omitted because the schema
  doesn't emit a `required` array (add them back if that changes).
