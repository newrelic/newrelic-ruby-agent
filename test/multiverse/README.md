# Multiverse

## Testing in a multitude of environments

Multiverse was created to solve a specific problem experienced by the Agent
team.  Not only does the New Relic Agent run in a wide variety of environments,
but its expected behavior *changes* based on the environment.  Instrumentation is
toggled on and off based on the presence of certain libraries, and some of these
libraries are incompatible with each other.  Effective testing requires us to
specify different environments for different tests; Multiverse aims to make this
painless.


## Getting started

You can invoke this via rake

    rake test:multiverse
  
The first time you run this command on a new Ruby installation, it will take quite a long time (up to 1 hour). This is because bundler must download and install each tested version of each 3rd-party dependency. After the first run through, almost all external gem dependencies will be cached, so things won't take as long.

## Running Specific Tests and Environments

Multiverse tests live in the test/multiverse directory and are organized into 'suites'. Generally speaking, a suite is a group of tests that share a common 3rd-party dependency (or set of dependencies). You can run a specific suite by providing a parameter (which gets loosely matched against suite names)

    rake test:multiverse[agent_only]

You can pass additional parameters to the test:multiverse rake task to control how tests are run:

- name= only tests with names matching string will be executed
- env= only the Nth environment will be executed (may be specified multiple times)
- file= only tests in specified file will be executed
- debug environments for each suite will be executed in serial rather than parallel (the default), and the pry gem will be automatically included, so that you can use it to help debug tests.

```
rake test:multiverse[agent_only,name=test_resets_event_report_period_on_reconnect,env=0,debug]
```


### Cleanup
Occasionally, it may be necessary to clean up your environment when migration scripts change or Gemfile lock files get out of sync.  Similar to Rails' rake assets:clobber, multiverse has a clobber task that will drop all multiverse databases in MySQL and remove all Gemfile.* and Gemfile.*.lock files housed under test/multiverse/suites/**

    rake test:multiverse:clobber








## Adding a test suite

To add tests add a directory to the `suites` directory.  This directory should
contain at least two files.

### Envfile

The Envfile is a meta gem file.  It allows you to specify one or more gemset
that the tests in this directory should be run against.  For example:

    gemfile <<-GEMFILE
      gem "rails", "~>3.2.0"
    GEMFILE

    gemfile <<-GEMFILE
      gem "rails", "~>3.1.0"
    GEMFILE

This will run these tests against 2 environments, one running rails 3.1, the
other running rails 3.2.

New Relic is automatically included in the environment.  Specifying it in the
Envfile will trigger and error.  You can override where newrelic is loaded from
using two environment variables.

The default gemfile line is

    gem 'newrelic_rpm', :path => '../../../ruby_agent'

`ENV['NEWRELIC_GEMFILE_LINE']` will specify the full line for the gemfile

`ENV['NEWRELIC_GEM_PATH']` will override the `:path` option in the default line.


### Test files

All files in a test suite directory that end with .rb will be executed as test
files.  These should use test unit.

For example:

    require 'test/unit'
    class ATest < Test::Unit::TestCase
      def test_json_is_loaded
        assert JSON
      end

      def test_haml_is_not_loaded
        assert !defined?(Haml)
      end
    end


## Testing Multiverse

You can run tests of multiverse itself with

    rake test:multiverse:self