# Guidelines for Contributing Code

At New Relic we welcome community code contributions to the Ruby Agent, and have
taken effort to make this process easy for both contributors and our development
team.

When contributing keep in mind that the agent runs in a wide variety of ruby
language implementations (e.g. 1.8.6, 1.8.7, 1.9.x, jruby, etc.) as well as a
wide variety of application environments (e.g. rails, sinatra, roll-your-own,
etc., etc.)

Because of this we need to be more defensive in our coding practices than most
projects.  Syntax must be compatible with all supported ruby implementations
(e.g. no 1.9 specific hash syntax) and we can't assume the presence of any
specific libraries such as `ActiveSupport`.

## Testing

The agent includes a suite of unit tests which should be used to verify your
changes don't break existing functionality.

### Running Tests

Running the test suite is simple.  Just invoke:

    bundle
    bundle exec rake

This will run the unit tests in standalone mode, bootstrapping a basic Rails
3.2 environment for the agent to instrument then executing the test suite.

These tests are setup to run automatically in
[travis-ci](https://travis-ci.org/newrelic/rpm) under several Ruby implementations.
When you've pushed your changes to github you can confirm that the travis-ci
build passes for your fork of the codebase.

Additionally, our own CI jobs runs these tests under multiple versions of Rails to
verify compatibility.

### Writing Tests

For most contributions it is strongly recommended to add additional tests which
exercise your changes.

This helps us efficiently incorporate your changes into our mainline codebase
and provides a safeguard that your change won't be broken by future development.

There are some rare cases where code changes do not result in changed
functionality (e.g. a performance optimization) and new tests are not required.
In general, including tests with your pull request dramatically increases the
chances it will be accepted.

