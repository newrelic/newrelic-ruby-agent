# Unit Tests

## Getting Started

We use Minitest for the Ruby agent.  The following command runs the unit tests without Rails:

    bundle exec rake test

## Running Specific Tests

You can also run a single unit test file like this:

    bundle exec ruby test/new_relic/agent_test.rb

And to run a single test within that file (note that when using the -n argument, you can either supply the entire test name as a string or a partial name as a regex):

    bundle exec ruby test/new_relic/agent_test.rb -n /test_shutdown/

## Running Tests in a Rails Environment

You can run against a specific Rails version only by passing the version name (which should match the name of a subdirectory in test/environments) as an argument to the test:env rake task, like this:

    bundle exec rake test:env[rails51]

In CI, these unit tests are run against all supported major.minor versions of Rails (as well as with Rails absent entirely). The test/environments directory contains dummy Rails apps for each supported Rails versions. You can also locally run tests against all versions of Rails supported by your current Ruby version with:

    bundle exec rake test:env

### Running Specific Tests

The file parameter can be added to the test:env invocation to run a specific unit file.  It can be exact file name, or a wildcard pattern.  Multiple file patterns can be specified by separating with a comma with no spaces surrounding:

    bundle exec rake test:env[rails60] file=test/new_relic/agent/distributed_tracing/*  # everything in this folder
    bundle exec rake test:env[rails60] file=test/new_relic/agent/tracer_state_test.rb   # single file
    bundle exec rake test:env[rails60] file=test/new_relic/agent/*_test.rb              # all *_test.rb files in this folder
    bundle exec rake test:env[rails60] file=test/new_relic/agent/distributed_tracing/*,test/new_relic/agent/datastores/*  # all files in two folders
