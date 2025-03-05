# Hybrid Agent Cross Agent Tests

These tests are drawn from the [Hybrid Agent Cross Agent Test Example][example] repository.

The file used to generate the test content can be found in [test/fixtures/cross_agent_tests/hybrid_agent.json][fixture]

The parser converts most keys to snake case to adhere with Ruby's standard naming practices.

## Updating the tests

The test fixture is not currently in the cross agent tests repo and will need to be manually updated until it is moved.
You can update the fixture by copying the [TestCaseDefinitions.json][test-cases] file and overwriting the
[hybrid-agent.json] file in our test fixtures.

If the fixture adds [a command][example-commands] that isn't already defined, add it to the `Commands` module.

If the fixture adds [an assertion parameter][example-rules], please update the `AssertionParameters` module.

The tests should fail with a helpful error message if either of these cases occur. Both the `Commands` and
`AssertionParameters` modules are included in the `HybridAgentTest`

At the time of their writing, the Ruby agent has not implemented Hybrid Agent functionality. The tests will fail if they
are run.

They have their own group in the [Multiverse::Runner module][runner], but it is not part of the CI, so it should not
execute.

At this time, only the OpenTelemetry::API methods are called. There is not an active SDK with a functional
TracerProvider running. This may need to change once we implement the Hybrid Agent functionality.

## Debugging

### focus_tests

The `HybridAgentTest` class includes a method, `#focus_tests` that can be used to run select tests based on the snake-
cased version of the corresponding `testDescription` key in the `hybrid_agent.json` fixture.

Example:
```ruby
# Update the focus_tests method with one or more testDescriptions you want to run
def focus_tests
  %w[does_not_create_segment_without_a_transaction]
end

```output
$ bermq hybrid_agent

...
# Running:

S.SSSSS

Fabulous run in 0.003526s, 1985.2524 runs/s, 1701.6449 assertions/s.

7 runs, 6 assertions, 0 failures, 0 errors, 6 skips
```

### ENABLE_OUTPUT
You can pass `ENABLE_OUTPUT=true` to the test to get a print out of all the evaluated JSON content. This can be helpful
to debug whether all levels of the test fixture are executed.

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
[example-commands]: https://github.com/nrcventura/HybridAgentCrossAgentTestExample/blob/main/README.md#commands
[example-rules]: https://github.com/nrcventura/HybridAgentCrossAgentTestExample/blob/main/README.md#rules
[test-cases]: https://github.com/nrcventura/HybridAgentCrossAgentTestExample/blob/main/TestCaseDefinitions.json
[fixture]: ../../../fixtures/cross_agent_tests/hybrid_agent.json
[runner]: ../../lib/multiverse/runner.rb
