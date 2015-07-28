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

If you only want to run some test suites you can filter by their names

    rake test:multiverse[sinatra]

You can run tests of multiverse itself with

    rake test:multiverse:self

### Adding a test suite

To add tests add a directory to the `suites` directory.  This directory should
contain at least two files.

#### Envfile

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


#### Test files

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

Multiverse has a suite of tests in the `test` directory for testing the
framework itself (sooo meta).  These help confirm that the system is working as
expected.
