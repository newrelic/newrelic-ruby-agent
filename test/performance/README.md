# Ruby Agent Performance Tests

This is a work-in-progress performance testing framework for the Ruby Agent. Feedback is welcome and encouraged - this ended up being more complex than I had originally imagined.

## Motivation

There are two main goals driving the development of this framework:

1. Add a way for automated performance tests to be run against the Ruby Agent and ingested into a system for tracking these results over time.
2. Provide a tool for Ruby Agent engineers to use while working on performance improvements.

## Examples

To start, here are a few examples of using the framework as it currently exists:

Run all tests, report detailed results in a human-readable form

```
$ ./test/performance/script/runner 
2 tests, 0 failures, 8.010997 s total

TransactionTracingPerfTests#test_short_transactions: 3.91854 s
  gc_runs: 58
  live_objects: 15543
  allocations: 3029802
  newrelic_rpm_version: 3.6.5.2.local
  ruby_version: ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]
  host: koan.local

TransactionTracingPerfTests#test_long_transactions: 3.575618 s
  gc_runs: 88
  live_objects: 122512
  allocations: 2416336
  newrelic_rpm_version: 3.6.5.2.local
  ruby_version: ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]
  host: koan.local

```

Run a specific test (test name matching is via regex):

```
$ ./test/performance/script/runner -n short
1 tests, 0 failures, 4.163766 s total

TransactionTracingPerfTests#test_short_transactions: 3.905195 s
  gc_runs: 58
  live_objects: 15543
  allocations: 3029802
  newrelic_rpm_version: 3.6.5.2.local
  ruby_version: ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]
  host: koan.local
```

Run all the tests, brief output (just timings):

```
$ ./test/performance/script/runner -b
2 tests, 0 failures, 7.917001 s total

TransactionTracingPerfTests#test_short_transactions: 3.909151 s
TransactionTracingPerfTests#test_long_transactions: 3.505083 s
```

Run all the tests, produce machine readable JSON output (for eventual ingestion into a storage system):

```
$ ./test/performance/script/runner -j | json_reformat
[
    {
        "suite": "TransactionTracingPerfTests",
        "name": "test_short_transactions",
        "elapsed": 3.882257,
        "details": {
            "gc_runs": 58,
            "live_objects": 8446,
            "allocations": 3029802,
            "newrelic_rpm_version": "3.6.5.2.local",
            "ruby_version": "ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]",
            "host": "koan.local"
        },
        "artifacts": [

        ]
    },
    {
        "suite": "TransactionTracingPerfTests",
        "name": "test_long_transactions",
        "elapsed": 3.502033,
        "details": {
            "gc_runs": 88,
            "live_objects": 132148,
            "allocations": 2416336,
            "newrelic_rpm_version": "3.6.5.2.local",
            "ruby_version": "ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]",
            "host": "koan.local"
        },
        "artifacts": [

        ]
    }
]
```

Run a specific test using the perftools.rb CPU profiler, producing a call-graph style PDF:

```
$ ./test/performance/script/runner -n short -i PerfToolsProfile
1 tests, 0 failures, 5.288594 s total

TransactionTracingPerfTests#test_short_transactions: 3.965765 s
  gc_runs: 58
  live_objects: 9268
  allocations: 3029801
  newrelic_rpm_version: 3.6.5.2.local
  ruby_version: ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]
  host: koan.local
  artifacts:
    /Users/ben/src/ruby_agent/artifacts/TransactionTracingPerfTests/test_short_transactions/PerfToolsProfile.pdf
```

Run with fewer iterations, and do object allocation profiling (again to a call-graph PDF):

```
$ CPUPROFILE_OBJECTS=1 ./test/performance/script/runner -n short -i PerfToolsProfile -N 1000
1 tests, 0 failures, 13.493219 s total

TransactionTracingPerfTests#test_short_transactions: 11.079068 s
  gc_runs: 3
  live_objects: 9096
  newrelic_rpm_version: 3.6.5.2.local
  ruby_version: ruby 1.9.3p327 (2012-11-10 revision 37606) [x86_64-darwin12.2.0]
  host: koan.local
  artifacts:
    /Users/ben/src/ruby_agent/artifacts/TransactionTracingPerfTests/test_short_transactions/PerfToolsProfile.pdf
```

## Writing tests

Performance tests are written in the style of `test/unit`: create a `.rb` file under `test/performance/suites`, subclass `Performance::TestCase`, and write test methods that start with `test_`. You can also write `setup` and `teardown` methods that will be run before/after each test.

Generally in your test, you'll want to do some operation N times (where N is large). You should base your N on the return value of `Performance::TestCase#iterations`, which is controlled by the `-N` command-line flag to `runner`. You may scale this value linearly as appropriate for your test if need be, but the idea is to have a single knob to turn that will change the iteration count for all tests.

The invocation of each `test_*` method will be timed, so any setup / teardown you need for your test that you don't want included in the timing should be confined to the `setup` and `teardown` methods.

## Test Isolation

Some initial testing suggested that certain kinds of tests would have a large impact on tests run later on in the same process (e.g. tests that create lots of long-lived objects will slow down all future GC runs for as long as those objects remain live).

In order to work around this problem the test runner will attempt to isolate each test to its own process by calling `Process.fork` right before running each test. Additionally, when operating in this mode, it will not require `newrelic_rpm` until *after* the fork call.

This means that your test cases must be loadable (though not necessarily runnable) without the `newrelic_rpm` gem avaiable.

## Adding instrumentation layers

The GC stats that are collected with each test run, and the perftools.rb profiling are examples of Instrumentors which can be wrapped around each test run.

This part of the test framework is still pretty rough, but the basic idea is that each instrumentor gets callbacks before and after each test, and add information to the test results, or attach artifacts (a fancy name for file paths, currently) to the result.

Instrumentors inherit from `Performance::Instrumentation::Instrumentor`, and may constrain themselves to running only on certain platforms (see `instrumentor.rb` for a list) by calling the `platforms` method in their class definitions. They may also signal that they should be used by default by calling `on_by_default`. They should imlement the `before`, `after` and `results` methods as follows:

The `before` method is called before each test is run. The test class and test name are passed as arguments.

The `after` method is called after each test is run. The test class, and test name are passed as arguments. Artifacts may be attached to the result here by appending to the `@artifacts` array. You may obtain paths to store artifacts at by calling `Performance::Instrumentation::Instrumentor#artifact_path` (see perf_tools.rb for an example).

The `results` method must return a Hash of key-value pairs to be attached to the `Result` object produced by running each test.

If your instrumentation layer needs to do one-time setup (requiring a gem, for example), implement the `setup` class method to do this setup.

## Unresolved Issues / Questions

1. **Have I created a monster?** What about this is stupid / over-engineered? What would you remove or simplify?
2. **Should this really be part of the agent source tree?** agent_prof has some cool features that allow you to run comparisons against arbitrary git revisions, but this is significantly more difficult to accomplish when the performance test harness is within the agent source tree itself. On the other hand, it's somewhat more convenient for automation if the performance tests live entirely withing the agent source tree.
3. **Should this be intergrated with multiverse?** I originally began by writing performance tests as an extension to multiverse, but ran into some issues around running unit tests in the same process as performance tests. Nothing insumountable, but a tangle nonetheless. The advantage of multiverse integration would be that we could more easily write performance tests that depended on 3rd-party gems.
4. **The fork-per-test thing won't work on JRuby.** To address this, I think we have a few options:
	1. Don't run performance tests on JRuby
	2. Run performance tests on JRuby, but don't worry about test isolation
	3. Use a mechanism like multiverse does to spawn a full new child process to run each test when under JRuby.
5. **Do we want to embed the concept of a 'run' into the machine-readable output?** Currently, the machine-readable output format produces a JSON array of records. Each record represents the results of running a single test, along with some metadata (e.g. Ruby version, host, agent version, etc). This is easy, and conceptually simple, but potentially stupidly inefficient: we're specifying some of the common metadata keys with *every* test result, rather than at a higher level with a group construct. Will we regret this?
6. **Can we think of a better namespace than `Performance`?**