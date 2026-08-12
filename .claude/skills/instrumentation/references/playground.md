# Playground test app (staging end-to-end)

After multiverse passes, create a standalone test app at `/Users/hramadan/ruby_agent_playground/<snake_name>/` that exercises the new instrumentation against the New Relic **staging** collector, **run it**, and verify the agent logs and audit logs are clean.

If the directory already exists, pause and ask (same shape as SKILL.md §1.2): abort / overwrite / leave alone.

Mirror the structure of an existing playground app (e.g. `/Users/hramadan/ruby_agent_playground/redis/` or `/bunny/`). Required files:

1. **`Gemfile`** — points `newrelic_rpm` at the local agent checkout, adds the gem being instrumented:

   ```ruby
   # frozen_string_literal: true
   source 'https://rubygems.org'

   gem 'newrelic_rpm', path: '../../newrelic-ruby-agent'
   gem '<gem-name>'
   ```

2. **`config/newrelic.yml`** — copy verbatim from a sibling playground app (e.g. `redis/config/newrelic.yml`); change ONLY the `app_name` to `"playground (<%= ENV['USER'] %> <ClassName> standalone)"`. The load-bearing lines that must stay are:
   - `license_key: <%= ENV['NEW_RELIC_LICENSE_KEY'] %>` — staging license key, sourced from env. Never check in a literal key. If `NEW_RELIC_LICENSE_KEY` is unset, tell the user where to grab it (1Password or the New Relic staging UI).
   - `host: staging-collector.newrelic.com`
   - `ssl: false`
   - `log_level: debug`, `audit_log.enabled: true`, `transaction_tracer.transaction_threshold: 0` (so every transaction is captured for inspection).

3. **`<snake_name>_test.rb`** — small script that boots the agent and exercises the wrapped methods inside a `ControllerInstrumentation`-tracked method:

   ```ruby
   # frozen_string_literal: true
   require 'newrelic_rpm'
   require '<gem-name>'

   class <ClassName>Experiment
     include NewRelic::Agent::Instrumentation::ControllerInstrumentation

     def <op>_test
       # call each wrapped method here against a real (or local) backend
     end

     add_transaction_tracer :<op>_test
   end

   ['log/newrelic_agent.log'].each { |log| File.truncate(log, 0) if File.exist?(log) }

   NewRelic::Agent.manual_start
   <ClassName>Experiment.new.<op>_test
   # sleep(30) if the gem's harvest needs to flush
   ```

4. **`README.md`** — one paragraph: how to run (`bundle install && NEW_RELIC_LICENSE_KEY=... bundle exec ruby <snake_name>_test.rb`), what to look for in `log/newrelic_agent.log`, and which staging app name to find in the New Relic UI.

## Running and verifying the playground

1. **License key.** Check that `NEW_RELIC_LICENSE_KEY` is set in the environment before running. If unset, ask the user to export it (from 1Password / the New Relic staging UI). Do not write the key into any file. Do not run without it set.

2. **Run.** From the playground app dir:

   ```bash
   bundle install
   bundle exec ruby <snake_name>_test.rb
   ```

   Wait for the agent to harvest before exiting — most playground scripts already include a `sleep` for this; add one (≥30s) if not.

3. **Pull the staging link.** Read `log/newrelic_agent.log` and find the line matching `INFO : Reporting to: <url>`. That URL is the user's staging APM entry — surface it verbatim to the user. Use:

   ```bash
   grep -m1 'INFO : Reporting to:' log/newrelic_agent.log
   ```

4. **Scan the agent log for errors related to the new instrumentation.** Grep `log/newrelic_agent.log` for `ERROR` and `WARN` lines, and for any line mentioning the gem name or the instrumentation module. Ignore noise unrelated to the new code (config-deprecation warnings, harmless connect retries). Surface anything that names the new instrumentation, references its segment kind, or originates from the wrapped method. If anything is unclear, show the line(s) to the user.

5. **Audit the audit log.** `log/newrelic_audit.log` shows the actual payloads sent to staging. Confirm the new instrumentation's outputs are present:
   - segments with the expected name (e.g. `Datastore/operation/<Product>/<op>`, `External/<host>/<library>/<verb>`, `MessageBroker/...`, or `Llm/<kind>/<Vendor>/<op>`)
   - expected metric names (the same ones the multiverse test asserted on)
   - for AI-LLM: the LLM event records (`LlmChatCompletionSummary`, `LlmEmbedding`, etc.)
   - segment attributes you set (`messaging.system`, `host`, `port_path_or_id`, etc.)

   `grep -E 'expected_pattern' log/newrelic_audit.log` is sufficient — don't try to parse the full payload. If something expected is missing, that's a real defect: stop and report it; don't claim success.

6. **Report.** Hand the user: the staging "Reporting to:" URL, a one-line "agent log clean / dirty (with N findings)" summary, and a one-line "audit log shows: [list of confirmed segments/metrics/events]" summary.
