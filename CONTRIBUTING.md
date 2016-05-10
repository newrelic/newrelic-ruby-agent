# Guidelines for Contributing Code

At New Relic we welcome community code contributions to the Ruby agent, and have
taken effort to make this process easy for both contributors and our development
team.

When contributing, keep in mind that the agent runs in a wide variety of Ruby
language implementations (e.g. 1.8.7, 1.9.x, 2.x.x, jruby, rbx, etc.) as well as
a wide variety of application environments (e.g. Rails, Sinatra, roll-your-own,
etc.) See https://docs.newrelic.com/docs/agents/ruby-agent/getting-started/new-relic-ruby#compat
for the current full list.

Because of this, we need to be more defensive in our coding practices than most
projects. Syntax must be compatible with all supported Ruby implementations
(e.g. no 1.9 specific hash syntax) and we can't assume the presence of any
specific libraries, including `ActiveSupport`, `ActiveRecord`, etc.

## Testing

The agent includes a suite of unit and functional tests which should be used to
verify your changes don't break existing functionality.

Unit tests are stored in the `test/new_relic` directory.

Functional tests are stored in the `test/multiverse` directory.

### Running Tests

Running the test suite is simple.  Just invoke:

    bundle
    bundle exec rake

This will run the unit tests in standalone mode, bootstrapping a basic Rails
3.2 environment for the agent to instrument, then executing the test suite.

These tests are setup to run automatically in
[Travis CI](https://travis-ci.org/newrelic/rpm) under several Ruby implementations.
When you've pushed your changes to GitHub, you can confirm that the Travis
build passes for your fork.

Additionally, our own CI jobs runs these tests under multiple versions of Rails
to verify compatibility.

### Writing Tests

For most contributions it is strongly recommended to add additional tests which
exercise your changes.

This helps us efficiently incorporate your changes into our mainline codebase
and provides a safeguard that your change won't be broken by future development.

There are some rare cases where code changes do not result in changed
functionality (e.g. a performance optimization) and new tests are not required.
In general, including tests with your pull request dramatically increases the
chances it will be accepted.

### Functional Testing

For cases where the unit test environment is not sufficient for testing a
change (e.g. instrumentation for a non-Rails framework, not available in the
unit test environment), we have a functional testing suite called multiverse.
These tests can be run by invoking:

    bundle
    bundle exec rake test:multiverse

More details are available in
[test/multiverse/README.md](https://github.com/newrelic/rpm/blob/master/test/multiverse/README.md).

### And Finally...

You are welcome to send pull requests to us - however, by doing so you agree
that you are granting New Relic a non-exclusive, non-revokable, no-cost license
to use the code, algorithms, patents, and ideas in that code in our products if
we so choose. Fortunately, you also agree the code is provided as-is and you provide no
warranties as to its fitness or correctness for any purpose.

If you have any feedback on how we can make contributing easier, please get in
touch at [support.newrelic.com](http://support.newrelic.com) and let us know!
