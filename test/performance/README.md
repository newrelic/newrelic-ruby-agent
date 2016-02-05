# Ruby Agent Performance Tests

This is a performance testing framework for the Ruby Agent.

## Motivation

There are two main goals driving the development of this framework:

1. Add a way for automated performance tests to be run against the Ruby Agent
   and ingested into a system for tracking these results over time.
2. Provide a tool for Ruby Agent engineers to use while working on performance
   improvements.

## Examples

### Invoking via rake task

Basic performance test invocations can be done using a rake task provided in the
newrelic_rpm Rakefile.

Run all performance tests, reporting results to the console:

```
$ rake test:performance
```

Run one specific suite:

```
$ rake test:performance[TransactionTracingPerfTests]
```

Run one specific suite and test (test name matching is via regex):

```
$ rake test:performance[TransactionTracingPerfTests,test_short_transactions]
```

### Invoking via the runner directly

More advanced options can be specified by invoking the runner script directly.
See `./test/performance/script/runner -h` for a full list of options.

Run all tests, report detailed results in a human-readable form

```
$ ./test/performance/script/runner
```

List all available test suites and names:

```
$ ./test/performance/script/runner -l
```

Run a specific test (test name matching is via regex):

```
$ ./test/performance/script/runner -n short
```

To compare results for a specific test between two versions of the code, use the
`-B` (for Baseline) and `-C` for (for Compare) switches:

```
$ ./test/performance/script/runner -n short -B
1 tests, 0 failures, 8.199975 s total
Saved 1 results as baseline.

... switch to another branch and run again with -C ...

$ ./test/performance/script/runner -n short -C
1 tests, 0 failures, 8.220509 s total
+-----------------------------------------------------+-----------+-----------+-------+---------------+--------------+--------------+
| name                                                | before    | after     | delta | allocs_before | allocs_after | allocs_delta |
|-----------------------------------------------------+-----------+-----------+-------+---------------+--------------+--------------|
| TransactionTracingPerfTests#test_short_transactions | 214.27 µs | 210.31 µs | -1.8% |            97 |           97 |         0.0% |
+-----------------------------------------------------+-----------+-----------+-------+---------------+--------------+--------------+
```

Run all the tests, produce machine readable JSON output (for eventual ingestion into a storage system):

```
$ ./test/performance/script/runner -j | json_reformat
```

Run a specific test under a profiler (either stackprof or perftools.rb, depending on your Ruby version):

```
$ ./test/performance/script/runner -n short --profile
```

Run with a set number of iterations, and do object allocation profiling (again to a call-graph dot file):

```
$ ./test/performance/script/runner -n short -a -N 1000
```

## Pointing at a different copy of the agent

If you want to run performance tests against an older copy of the agent that
doesn't have the performance test framework embedded within it, you can do that
by specifying the path to the agent you want to test against by passing the `-A`
flag to the `runner` script, or by setting the `AGENT_PATH` environment variable
when using the rake task.


## Writing tests

Performance tests are written in the style of `test/unit`: create a `.rb` file
under `test/performance/suites`, subclass `Performance::TestCase`, and write
test methods that start with `test_`. You can also write `setup` and `teardown`
methods that will be run before/after each test.

Within your `test_` method, you must call `measure` and pass it a block
containing the code that you'd like to actually measure the timing of. This
allows you to do test-specific setup that doesn't get counted towards your
test timing.

The block that you pass to `measure` will automatically be run in a loop for a
fixed amount of time by the performance runner harness (5s by default), and the
number of iterations performed will be recorded so that measurements can be
normalized to per-iteration values.

You can look at the [existing tests](suites) for examples.

## Test Isolation

Initial testing suggested that certain kinds of tests would have a large impact
on tests run later on in the same process (e.g. tests that create lots of
long-lived objects will slow down all future GC runs for as long as those
objects remain live).

In order to address this problem, the test runner will attempt to isolate each
test to its own process by re-spawning itself for each test invocation. This is
done using `IO.popen` rather than `Process.fork` in order to maintain
compatibility with JRuby.

Additionally, when operating in this mode, the `newrelic_rpm` gem will not be
loaded until *after* the fork call. This means that your **test cases must be
loadable (though not necessarily runnable) without the `newrelic_rpm` gem
available**.

Not all command-line options to the runner work with this test isolation yet.
You can disable it by passing the `-I` or `--inline` flag to the runner.

## Adding instrumentation layers

The GC stats that are collected with each test run, and the perftools.rb
profiling are examples of Instrumentors which can be wrapped around each test run.

The basic idea is that each instrumentor gets callbacks before and after each
test, and add information to the test results, or attach artifacts (a fancy name
for file paths, currently) to the result.

Instrumentors inherit from `Performance::Instrumentation::Instrumentor`, and may
constrain themselves to running only on certain platforms (see `instrumentor.rb`
for a list) by calling the `platforms` method in their class definitions. They
may also signal that they should be used by default by calling `on_by_default`.
They should implement the `before`, `after` and `results` methods as follows:

The `before` method is called before each test is run. The test class and test
name are passed as arguments.

The `after` method is called after each test is run. The test class, and test
name are passed as arguments. Artifacts may be attached to the result here by
appending to the `@artifacts` array. You may obtain paths to store artifacts at
by calling `Performance::Instrumentation::Instrumentor#artifact_path` (see
perf_tools.rb for an example).

The `results` method must return a Hash of key-value pairs to be attached to the
`Result` object produced by running each test.

If your instrumentation layer needs to do one-time setup (requiring a gem, for
example), implement the `setup` class method to do this setup.
