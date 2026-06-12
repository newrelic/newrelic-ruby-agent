---
name: instrumentation
description: Scaffold a complete New Relic Ruby agent instrumentation for a third-party gem in this repo. Use when the user asks to "instrument <gem>", "add instrumentation for <gem>", "scaffold a new instrumentation", or names a datastore / HTTP-client / messaging / AI-LLM gem and asks the Ruby agent to trace it. Generates the seven-file prepend+chain layout under `lib/new_relic/agent/instrumentation/<name>/`, a runnable multiverse suite under `test/multiverse/suites/<name>/`, registers config in `default_source.rb`, and adds the gem to `supported_gems.txt`. Does NOT commit, push, or open PRs.
---

You are scaffolding instrumentation for one third-party Ruby gem in the newrelic-ruby-agent repo. Produce working agent code + a passing multiverse suite. Never commit, push, or open PRs (per the project CLAUDE.md). The agent has zero runtime gem dependencies — instrumentation must use only Ruby stdlib plus agent helpers under `NewRelic::Agent::*`. Every `.rb` file you create must begin with this exact 3-line header:

```
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
```

When you don't know something — call it out and ask. Don't guess at gem APIs, version floors, or LLM event classes.

## Asking with code previews

Whenever the user is choosing between code shapes — which class/method to wrap, the wrapper method signature, an LLM event class, an alternative attribute style, two valid prepend forms — use `AskUserQuestion` with the `preview` field set to a concrete Ruby snippet for each option. The snippet should be the actual code that would land in the file, 5–15 lines, ceremony stripped (no license header, no `frozen_string_literal`) so the diff between options is what's visible.

Example shape for a "which method to wrap" question:

```text
Option A — Foo::Client#request
  module Prepend
    def request(req, body = nil, &block)
      request_with_new_relic(req) { super }
    end
  end

Option B — Foo::Connection#perform
  module Prepend
    def perform(req)
      perform_with_new_relic(req) { super }
    end
  end
```

Use code previews for: target class + method choices (§1.5), LLM event class selection (§5 AI-LLM — show the event constructor and which segment attribute it populates), datastore statement style (`notice_sql` vs `notice_nosql_statement` — show the resulting trace-node attribute), and any time two valid implementations differ in a way the user should see before picking. Don't use previews for prose preferences (live-verify yes/no, version floor) — labels suffice there.

## Agent spec

Before any other planning, ask the user whether there is an **agent spec** that governs this instrumentation. Agent specs are New Relic's cross-language contracts that define what an instrumentation must emit (segment names, event types, required attributes, distributed-tracing behavior, etc.) — the spec is the source of truth, and Ruby is one implementation of it. If a spec exists for this gem or category, the design preview in §3 must be derived from the spec, not invented from peer instrumentations alone.

Ask the user, in this order, and do NOT proceed to §1 until they answer:

1. **"Is there an agent spec for this instrumentation? If so, paste the path (local file) or link (Confluence / GitHub / wiki / PDF)."** Accept "no spec" — many gems have none — but ask explicitly so the question isn't skipped.
2. If a path/link is provided, **read it before planning**. For local paths, use `Read`. For URLs, use `WebFetch`. For PDFs, use `Read` with the `pages` arg. If the spec is somewhere the skill can't reach (private Confluence behind SSO, etc.), ask the user to paste the relevant excerpts inline.
3. After reading, **ask any clarifying questions** the spec leaves open: ambiguous segment names, attributes you don't recognize, version-gating language, OTel mappings, required vs. optional outputs, anything that would change what you emit. Don't move on with assumptions.
4. Reflect back to the user, in 3–6 bullets, what the spec mandates for this gem (segment kind, required attributes, event types, distributed-tracing behavior). The user confirms before §1.

If the user says no spec exists, proceed to §1 — but in §3's design preview, name the peer instrumentations whose conventions you're inheriting (e.g. "no spec; following ruby_kafka for Kafka conventions"), so the user can sanity-check the inheritance.

## 1. Inputs to gather first

Resolve in order before writing anything:

1. **Names**: raw gem name, `snake_name = name.downcase.tr('-', '_')`, and `class_name` via `NewRelic::LanguageSupport.camelize(name)`. The directory and config key use snake form; `supported_gems.txt` uses the rubygems.org form (preserve dashes — e.g. `ruby-openai`, not `ruby_openai`).

   **Acronym-casing check.** Camelize lowercases acronyms (`NetHttp`, `RubyOpenai`), but several existing instrumentations preserve them (`NetHTTP`, `OpenAI`, `HTTPrb`). If the gem name contains an acronym, code-preview both forms and let the user pick. Default to whatever the canonical reference for the category does.
2. **Collision check**: if `lib/new_relic/agent/instrumentation/<snake_name>.rb` OR `test/multiverse/suites/<snake_name>/` exists, STOP and ask the user: abort / overwrite / augment with a new method. Do not proceed silently.
3. **Gem source path**: run `bundle show <name>`. If it fails, ask the user for the path or for them to add the gem to a Gemfile and `bundle install`. Read the gem's main entry file and public API from there before classifying. **While reading, run the Shape decision check below** — many gems expose their own instrumentation hooks, and detecting that BEFORE picking a category changes the entire file layout.
4. **Category** (see §2). Auto-decide if the shape clearly matches one of the four canonical references; pause and ask otherwise. AI-LLM ALWAYS pauses for confirmation.
5. **Target class + method(s)** to wrap. Read the gem source, propose 1–3 candidate entry points, confirm with user when more than one is plausible. Show each candidate as a code preview (the resulting `Prepend` module body) so the user can compare wrapping shapes side-by-side.
6. **Oldest supported gem version**: read the gem's `CHANGELOG.md` / `HISTORY.md` / git tags. Pick the oldest release that still exposes the API you're wrapping. If undetermined, ask the user.
7. **Backing service**: does this gem talk to a real server in tests (Redis / Postgres / RabbitMQ / etc.)? If yes, ask upfront: attempt live verification, or skip? If yes-but-unreachable, look for a `docker-compose.yml` in the suite dir or repo root and offer to run `docker compose up`. Never start services without explicit confirmation.

## Shape decision (hooks before prepend/chain)

Before §2 (category), decide what *shape* of instrumentation this gem needs. The default skill flow assumes you'll monkey-patch the gem via `prepend` (or `chain` fallback) — but many gems expose their own first-class instrumentation hooks, and using those is **always preferred** when available: hooks are public API, stable across gem versions, immune to internal refactors, and don't require the chain-vs-prepend dance.

**Search the gem source for hook APIs.** Grep for these names in the gem you ran `bundle show` on:

```bash
grep -RInE 'subscribe|Instrumentation|Notifications|Middleware|tracer|Subscriber|on_event|register_handler' <gem-path>/lib | head -50
```

Common hook APIs you'll encounter:

- `Stripe::Instrumentation.subscribe(:request_begin) { |event| ... }` — Stripe ≥5.38.0 ships an event API; the real `stripe.rb` instrumentation uses it (no monkey-patching).
- `ActiveSupport::Notifications.subscribe('sql.active_record') { |*args| ... }` — Rails subscribers (used by ActiveRecord, ActionController, ActionView, ActionCable).
- `GraphQL::Schema.tracer(...)` — graphql-ruby exposes a tracer protocol; instrumentations register a tracer class.
- `Sidekiq.configure_server { |c| c.server_middleware { |chain| chain.add ... } }` — Sidekiq has client + server middleware chains.

If you find a hook API, **prefer it**. Confirm with the user via `AskUserQuestion` (show a code preview of the prepend approach vs the hook approach) so they can sanity-check.

### File layout for hook-based instrumentations

The standard 7-file layout in §4 does NOT apply. Use this 2-file flat layout instead (model after `lib/new_relic/agent/instrumentation/stripe.rb` + `stripe_subscriber.rb`):

1. `lib/new_relic/agent/instrumentation/<snake_name>.rb` — DependencyDetection block that registers the subscriber/middleware/tracer with the gem's hook API. Skeleton:

   ```ruby
   require 'new_relic/agent/instrumentation/<snake_name>_subscriber'

   DependencyDetection.defer do
     named :<snake_name>

     depends_on { defined?(<Const>) && NewRelic::Helper.version_satisfied?(<Const>::VERSION, '>=', '<floor>') }

     executes do
       subscriber = NewRelic::Agent::Instrumentation::<ClassName>Subscriber.new
       <Const>::Instrumentation.subscribe(:request_begin) { |e| subscriber.start_segment(e) }
       <Const>::Instrumentation.subscribe(:request_end)   { |e| subscriber.finish_segment(e) }
     end
   end
   ```

2. `lib/new_relic/agent/instrumentation/<snake_name>_subscriber.rb` — a plain Ruby class (not a module) with `start_segment(event)` / `finish_segment(event)` (or whatever the hook signature dictates). Each method:
   - guards on `NewRelic::Agent::Tracer.state.is_execution_traced?`
   - opens / finishes the segment
   - rescues + `logger.error` so a subscriber bug never breaks the user's app

NO `<snake_name>/` subdirectory. NO `prepend.rb`. NO `chain.rb`. NO `instrumentation.rb` mixin module.

**Multiverse Envfile.** The harness still requires an `instrumentation_methods` line, but for hook-based gems use `:chain` only with the explanatory comment:

```ruby
# While <gem> instrumentation doesn't do any monkey patching, we need to
# include an instrumentation method for multiverse to run the tests
instrumentation_methods :chain
```

**Tests.** In addition to asserting on segment metrics/attributes, **assert that the subscriber is actually registered**. For Stripe-style APIs:

```ruby
def test_subscribed_request_begin
  subscribers = Stripe::Instrumentation.send(:subscribers)
  newrelic = subscribers[:request_begin].detect { |_k, v| v.to_s.include?('instrumentation/stripe') }
  assert(newrelic)
end
```

The skill's standard `<method>_with_new_relic` / `_without_new_relic` patterns from §4 don't apply when there's no method to wrap. Skip §4 file items 2–5 and §5 per-category playbook entirely; they're for monkey-patch shapes.

## 2. Category decision tree

Auto-decide if the gem's shape clearly matches a reference. For each branch, `Read` the canonical reference's `instrumentation.rb` and main test file before generating. **If the Shape decision above resolved to hook-based, skip this — the category bullets below assume monkey-patching.**

- **Datastore** (SQL / KV / cache / document store) → ref `lib/new_relic/agent/instrumentation/redis/`
- **External HTTP** (HTTP client) → ref `lib/new_relic/agent/instrumentation/net_http/`
- **Messaging** (queue / broker / job runner) → ref `lib/new_relic/agent/instrumentation/aws_sqs/`
- **AI-LLM** (chat / embeddings / tool-use) → ref `lib/new_relic/agent/instrumentation/ruby_openai/` — ALWAYS pause to confirm
- **Other / ambiguous** → ask the user which fits

**Also read peer instrumentations in the same library family.** The canonical reference covers the *category* (e.g. aws_sqs for messaging) but not necessarily the *library family* (Kafka, GraphQL, Postgres-flavored, etc.). When the gem you're wrapping has a sibling already instrumented in the agent, that sibling matters more than the canonical reference for naming, attributes, and metric shape. Examples that have surfaced real defects:

- Wrapping **rdkafka** → read **`ruby_kafka/`** (same Kafka conventions: `MessageBroker/Kafka/Nodes/<host>/...` metrics, separate Producer / Consumer / Config wrap, `wrap_message_broker_consume_transaction` for streaming consume).
- Wrapping **opensearch** → read **`elasticsearch/`** (same query / index conventions).
- Wrapping a new **AWS SDK** client (Kinesis, DynamoDB, etc.) → read the existing **`aws_*/`** directories.
- Wrapping a new **HTTP client** → read multiple of `net_http/`, `httprb/`, `httpx/`, `excon/` (they share an HTTPClient wrapper protocol — see `lib/new_relic/agent/http_clients/`).
- Wrapping a new **AI/LLM** vendor → read **`ruby_openai/`** AND **`bedrock/`** for parallel patterns.

`ls lib/new_relic/agent/instrumentation/` and grep the gem's domain words (kafka, http, aws, llm, sql, mongo, graphql, etc.) to find peers BEFORE writing files. If there's a peer, copy its segment/metric/attribute conventions verbatim — uniformity across siblings is a stronger constraint than category-canonical purity.

## 3. Design preview

Before writing any files, show the user a concrete preview of what the instrumentation will produce when the wrapped methods run — the actual metric names, span/segment names, transaction trace nodes, events, and **the segment attributes you'd attach** (see §5 for the attribute philosophy). This is a confirmation checkpoint: the user either approves and you proceed to §4, or they redirect (different segment name, missing or extra attributes, wrong event class) and you regenerate the preview.

Format the preview as a single block with these sections, populated for the specific gem and methods you're wrapping. Use realistic example values (the actual host/port/queue/model the test app would hit), not placeholders like `<host>`.

```text
For `<gem-name>` wrapping `<TargetClass>#<method>` (×N methods), running this instrumentation would emit:

Metrics
  - <Concrete metric name 1>
  - <Concrete metric name 2>
  - Supportability/<Library>/Invoked
  - <any extra Supportability metric, e.g. Supportability/Ruby/ML/<Vendor>/<VERSION>>

Segments / spans (in transaction trace + distributed traces)
  - name: <segment name>
    kind: <Datastore | External | MessageBroker | Llm>
    attributes:
      <attr>: <example value>
      ...

Transaction trace nodes
  - <node name> (same as segment) with attributes <list>

Events (AI-LLM only)
  - <EventClass> (e.g. LlmChatCompletionSummary)
    fields: <id, model, request.max_tokens, response.choices[].finish_reason, ...>
```

Worked examples for each canonical category — Datastore, External HTTP, Messaging, AI-LLM — live in [references/design-previews.md](references/design-previews.md). Read the entry matching the gem you're instrumenting, adapt the example values to what the test app would actually hit, and assemble the preview block above using those metric/segment/event names verbatim.

If the user wants to see a side-by-side of two design alternatives (e.g. should the operation be `chat` or `completion`?), use `AskUserQuestion` with each option's `preview` rendering the relevant slice of the block above. Once the design is confirmed, the multiverse test in §4 asserts on exactly these metric/segment/event names — keep them in sync.

## 4. File generation contract

Write exactly these files with the `Write` tool. Do not invoke `thor instrumentation:scaffold` — replace it.

**Argument forwarding (applies to every wrapper method):** read the gem's source for the wrapped method first, then write the wrapper to **mirror its signature exactly** — kwargs only if the gem takes kwargs, positional/optional/block exactly as declared. Don't add `*args` "just in case." Pause and ask the user if unsure.

The agent supports Ruby 2.6+, so when you splat, use the explicit `*args, **kwargs, &block` form (NOT `(...)`, which is 2.7+). Never write `def method(*args)` alone — it silently drops kwargs on Ruby 3+. The same mirroring rule applies to the prepend method and the chain `_without_new_relic` alias.

1. `lib/new_relic/agent/instrumentation/<snake_name>.rb` — DependencyDetection block:

   ```ruby
   DependencyDetection.defer do
     named :<snake_name>

     depends_on { defined?(<ClassName>) }
     # Add `conflicts_with_prepend { defined?(...) }` ONLY if the canonical reference for this category does.

     executes do
       require_relative '<snake_name>/instrumentation'

       if use_prepend?
         require_relative '<snake_name>/prepend'
         prepend_instrument <TargetClass>, NewRelic::Agent::Instrumentation::<ClassName>::Prepend
       else
         require_relative '<snake_name>/chain'
         chain_instrument NewRelic::Agent::Instrumentation::<ClassName>::Chain
       end
     end
   end
   ```

2. `lib/new_relic/agent/instrumentation/<snake_name>/instrumentation.rb` — core module under `NewRelic::Agent::Instrumentation::<ClassName>`. Define `INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)` and one `<method>_with_new_relic(*args, **kwargs)` per wrapped method (kwargs only if the gem method takes them). Each wrapper:
   - calls `NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)`
   - opens a category-appropriate segment (see [references/playbooks.md](references/playbooks.md) for the per-category Tracer entry-point)
   - wraps `yield` in `NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }`
   - finishes the segment in an `ensure`: `segment&.finish`
   - rescues exceptions raised while *constructing* the segment so the gem call still runs (`logger.error` and continue without the segment — see `aws_sqs` for the pattern)
   - **Recursion check** — read the gem source for the wrapped method. If it can call itself (directly or via a sibling method that re-enters the wrapped one — Net::HTTP's `start` re-calls `request`; many connection-pool / retry libraries do similar), wrap the `yield` in `NewRelic::Agent.disable_all_tracing { ... }` to prevent double-counted segments and metrics. Skipping this on a recursive method silently inflates external/datastore counts. If unsure whether the method is recursive, ask the user before deciding.

3. `lib/new_relic/agent/instrumentation/<snake_name>/prepend.rb` — `module Prepend`, `include` the core module, redefine each wrapped method with full forwarding:

   ```ruby
   def <method>(*args, **kwargs, &block)
     <method>_with_new_relic(*args, **kwargs) { super }
   end
   ```

   `super` with no parens auto-forwards args + block. Drop `**kwargs` only if the gem method definitively takes none — verify against the gem source.

4. `lib/new_relic/agent/instrumentation/<snake_name>/chain.rb` — `module Chain` with `self.instrument!` that does `::<TargetClass>.class_eval do ... end`: `include` the core module, `alias_method :<method>_without_new_relic, :<method>`, redefine `<method>` with full forwarding:

   ```ruby
   def <method>(*args, **kwargs, &block)
     <method>_with_new_relic(*args, **kwargs) do
       <method>_without_new_relic(*args, **kwargs, &block)
     end
   end
   ```

5. `lib/new_relic/agent/instrumentation/<snake_name>/constants.rb` — **datastore-style only** (or when the canonical reference has one). Holds `PRODUCT_NAME` and operation-name constants.

6. `test/multiverse/suites/<snake_name>/Envfile` — `instrumentation_methods :chain, :prepend`, then a 2-entry matrix:

   ```ruby
   <SNAKE_NAME>_VERSIONS = [
     [nil],
     ['<oldest_supported>']
   ]

   def gem_list(version = nil)
     <<~RB
       gem '<gem-name>'#{version}
     RB
   end

   create_gemfiles(<SNAKE_NAME>_VERSIONS)
   ```

   If only one version is supportable, fall back to inline `gemfile <<~RB; gem '<name>'; RB`.

7. `test/multiverse/suites/<snake_name>/<snake_name>_instrumentation_test.rb` — Minitest with `MultiverseHelpers` + `setup_and_teardown_agent`. Tests must:
   - call the gem's real methods inside `in_transaction { ... }` blocks
   - assert on **agent-side outputs**: metric names, segment attributes, LLM events. Never assert on the gem's own behavior.
   - use `assert_metrics_recorded`, `assert_metrics_recorded_exclusive(expected, ignore_filter: /Supportability/)`, and walk `last_transaction_trace.root_node.children[i]` for attribute checks (`node[:host]`, `node[:port_path_or_id]`, etc.)
   - call `NewRelic::Agent.drop_buffered_data` between tests when residual metrics from setup would skew assertions

   **Shared TestCases module.** Before writing bespoke tests, run `find test/new_relic -name '*test_cases*'` and `grep -rli '<category>' test/new_relic` for a shared module that the category already standardizes on (e.g. HTTP-client instrumentations all `include NetHttpTestCases` / `HttpClientTestCases`, exposing a 30-test conformance suite). If one matches the category, the multiverse test file should `include` it and provide the gem-specific hooks (`get_response`, `client_name`, `request_instance`, etc.) — that's how the canonical references like `httprb_test.rb` and `httpx_test.rb` keep coverage uniform. Bespoke tests on top of the shared module are fine, but starting from scratch when a shared module exists is a coverage gap.

8. `test/multiverse/suites/<snake_name>/config/newrelic.yml` — copy from the canonical reference's config; the load-bearing line is `instrumentation:\n  <snake_name>: <%= $instrumentation_method %>`.

## 5. Per-category playbook

**Add attributes when they help.** Beyond the attributes the Tracer entry-point sets automatically (host/port for datastore, uri/procedure for external, etc.), look at what the gem hands you in the wrapped method's arguments and the response — and attach anything a user would want when investigating in New Relic. Use `segment.add_agent_attribute('<key>', <value>)` for facts about the call (region, account ID, queue ARN, model name, request size, status code, error class), and prefer the New Relic / OpenTelemetry-aligned keys you see in the canonical references (`messaging.system`, `cloud.region`, `cloud.account.id`, `messaging.destination.name`, `db.system`, `http.statusCode`, etc.) over inventing new ones. Skip attributes that would be PII (request bodies, message contents, user identifiers) unless the agent already has a config flag governing them. If you're unsure whether an attribute is useful, list the candidates and ask the user — show each in the §3 design preview so they're agreed before you write the wrapper. Whatever attributes you add, the multiverse test must assert on them.

Per-category mechanics — which `Tracer` entry-point to call, the attribute conventions, the metric assertions the multiverse test must make — live in [references/playbooks.md](references/playbooks.md), one entry each for Datastore / External HTTP / Messaging / AI-LLM. Read the entry matching the category resolved in §2 before generating §4 file 2 (the core `instrumentation.rb`).

## 6. Registry edits

**`lib/new_relic/agent/configuration/default_source.rb`** — append the entry below in alphabetical position among the existing `:'instrumentation.<x>'` keys (grep for surrounding entries, then `Edit` between them). Indent with 8 spaces. Don't drift from this exact key shape:

```ruby
        :'instrumentation.<snake_name>' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the <name> library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
```

**`.github/workflows/scripts/slack_notifications/supported_gems.txt`** — alphabetical insert (the file is sorted). Use the rubygems.org form, dashes preserved.

## 7. Verification gate

Run in this order. Cap iterations at 5 — beyond that, stop and surface to the user.

```bash
bundle exec rubocop lib/new_relic/agent/instrumentation/<snake_name>.rb \
                    lib/new_relic/agent/instrumentation/<snake_name>/ \
                    test/multiverse/suites/<snake_name>/
bundle exec rake 'test:multiverse[<snake_name>]'
```

Pass criteria: rubocop has zero offenses (use `-a` for style autofixes; never `-A`); multiverse passes for both `chain` and `prepend` across both Envfile entries.

If the multiverse run reports the backing service is unreachable: stop, name the service / port, look for `docker-compose.yml` (suite dir → repo root), offer to run it. Don't start services unprompted.

Debug invocations:
- single method: `bundle exec rake 'test:multiverse[<snake_name>,method=prepend]'`
- single env: `bundle exec rake 'test:multiverse[<snake_name>,env=0]'`
- single test: `bundle exec rake 'test:multiverse[<snake_name>,name=test_foo,debug]'`

## 8. Playground test app (staging end-to-end)

After multiverse passes, create a standalone test app in the ruby_agent_playground repository that exercises the new instrumentation against the New Relic **staging** collector, run it, and verify the agent + audit logs. Use `AskUserQuestion` for their path to the ruby_agent_playground repository where the test shoud be created.

Full setup (Gemfile / `config/newrelic.yml` / test script / README templates) and the run-and-verify checklist (license-key check → run → pull staging link → scan agent log → audit the audit log → report) live in [references/playground.md](references/playground.md). Read that file before generating playground files.

## 9. Reporting back

End-of-run summary, plain prose:
- Files created in the agent repo (paths, count).
- Files appended (`default_source.rb`, `supported_gems.txt`).
- Playground app path.
- Verification: rubocop pass/fail; multiverse pass/fail per method + env; whether live verification was skipped and why.
- **Staging URL** — the `INFO : Reporting to: <url>` line from the agent log, surfaced verbatim.
- Agent log scan: clean, or N findings (with the offending lines quoted).
- Audit log scan: list of confirmed segments / metrics / LLM events; flag anything expected but missing.
- Reminder: nothing was committed, pushed, or PR'd.

## 10. Failure modes

- Multiverse rake doesn't pick up the suite → check that the suite directory exists and the `Envfile` parses; surface the error without auto-recovery.
- Backing service down + no docker-compose found → skip live verification, report.
- `/Users/hramadan/ruby_agent_playground/` missing → ask user for the playground path; do not auto-create the parent repo.
- `INFO : Reporting to:` line missing from the agent log → the agent never connected. Surface the connect-related ERROR/WARN lines (license key invalid, host unreachable, SSL mismatch, etc.) and stop; don't claim success.
