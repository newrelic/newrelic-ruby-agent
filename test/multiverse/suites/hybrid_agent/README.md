# Hybrid Agent Cross Agent Tests

These tests are drawn from the [Hybrid Agent Cross Agent Test Example][example] repository.

The file used to generate the test content can be found in [test/fixtures/cross_agent_tests/hybrid_agent.json][fixture]

At the time of their writing, the Ruby agent has not implemented Hybrid Agent functionality. The tests will fail if they are run.

They have their own group in the [Multiverse::Runner module][runner], but it is not part of the CI, so it should not executed.

You can pass `ENABLE_OUTPUT=true` to the test to get a print out of all the evaluated JSON content. This can be helpful to debug whether all levels of the test fixture are being executed.

Example:
```shell
$ ENABLE_OUTPUT=true bermq hybrid_agent

TEST: does_not_create_segment_without_a_transaction
do_work_in_span
{span_name: "Bar", span_kind: :internal}
The OpenTelmetry span should not be created
{"operator" => "NotValid", "parameters" => {"object" => "currentOTelSpan"}}
current_otel_span
There should be no transaction
{"operator" => "NotValid", "parameters" => {"object" => "currentTransaction"}}
current_transaction
Agent Output: transactions: []
Agent Output: spans: []
...
```

[example]: https://github.com/nrcventura/HybridAgentCrossAgentTestExample
[fixture]: ../../../fixtures/cross_agent_tests/hybrid_agent.json
[runner]: ../../lib/multiverse/runner.rb
