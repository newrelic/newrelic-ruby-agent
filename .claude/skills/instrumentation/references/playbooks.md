# Per-category playbook

Read the entry that matches the category resolved in §2 of SKILL.md. The general "add attributes when they help" attribute philosophy is in SKILL.md §5 and applies regardless of category — this file holds only the per-category mechanics (which Tracer entry-point to call, which assertions the multiverse test must make).

## Datastore

Open `Tracer.start_datastore_segment(product:, operation:, host:, port_path_or_id:, database_name:)`. Use `segment.notice_nosql_statement(stmt)` (NoSQL) or `segment.notice_sql(sql)` (SQL). Tests assert on `Datastore/operation/<Product>/<op>`, `Datastore/instance/<Product>/<host>/<port>`, and the `[:host], [:port_path_or_id], [:database_name]` attributes on the trace node.

## External HTTP

Open `Tracer.start_external_request_segment(library:, uri:, procedure:)`. If the gem has request/response objects you can wrap, add `lib/new_relic/agent/http_clients/<name>_wrappers.rb` and call `segment.add_request_headers(wrapper)` + `segment.process_response_headers(wrapper)`. Tests assert on `External/<host>/<library>/<verb>`.

## Messaging

Open `Tracer.start_message_broker_segment(action: :produce | :consume, library:, destination_type: :queue | :topic | :exchange, destination_name:)`. Add `segment.add_agent_attribute('messaging.system', '<gem>')` and any cloud / destination attributes. Tests assert on `MessageBroker/<library>/<destination_type>/<action>/Named/<destination>`.

## AI-LLM

Open `Tracer.start_segment(name: 'Llm/<kind>/<Vendor>/<op>')`. Build an LLM event object — `NewRelic::Agent::Llm::ChatCompletionSummary`, `Embedding`, etc.; if the right class isn't obvious, list the `NewRelic::Agent::Llm::*` classes in the repo and ask, with each option's `preview` showing the actual constructor call (`event = NewRelic::Agent::Llm::ChatCompletionSummary.new(id: ..., model: ..., ...)`) so the user picks based on the fields it populates. Assign `segment.llm_event = event`. Record `Supportability/Ruby/ML/<Vendor>/<VERSION>` via `NewRelic::Agent.record_metric(..., 0.0)`. Pass VENDOR as the third arg to `prepend_instrument`. Gate the whole instrumentation on `ai_monitoring.enabled`.
