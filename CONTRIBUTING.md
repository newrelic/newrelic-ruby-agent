# Guidelines for Contributing Code

At New Relic we welcome community code contributions to the Ruby agent, and have
taken effort to make this process easy for both contributors and our development
team.

When contributing, keep in mind that the agent runs in a wide variety of Ruby
language implementations (e.g. 2.x.x, jruby, etc.) as well as a wide variety of
application environments (e.g. Rails, Sinatra, roll-your-own, etc.) See
https://docs.newrelic.com/docs/agents/ruby-agent/getting-started/ruby-agent-requirements-supported-frameworks
for the current full list.

Because of this, we need to be more defensive in our coding practices than most
projects. Syntax must be compatible with all supported Ruby implementations and
we can't assume the presence of any specific libraries, including `ActiveSupport`,
`ActiveRecord`, etc.

## Branches

The head of `main` will generally have New Relic's latest release. However,
New Relic reserves the ability to push an edge to the `main`. If you download a
release from this repo, use the appropriate tag. New Relic usually pushes beta
versions of a release to a working branch before tagging them for General
Availability.

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
[test/multiverse/README.md](https://github.com/newrelic/newrelic-ruby-agent/blob/main/test/multiverse/README.md).

### Contributor License Agreement

Keep in mind that when you submit your Pull Request, you'll need to sign the CLA via the click-through using CLA-Assistant. If you'd like to execute our corporate CLA, or if you have any questions, please drop us an email at opensource@newrelic.com.

For more information about CLAs, please check out Alex Russell’s excellent post,
[“Why Do I Need to Sign This?”](https://infrequently.org/2008/06/why-do-i-need-to-sign-this/).

### Slack

We host a public Slack with a dedicated channel for contributors and maintainers of open source projects hosted by New Relic.  If you are contributing to this project, you're welcome to request access to the #oss-contributors channel in the newrelicusers.slack.com workspace.  To request access, see https://newrelicusers-signup.herokuapp.com/.

### And Finally...

Please note, we only accept pull requests for versions of this project v6.12.0 or greater.

If you have any feedback on how we can make contributing easier, please get in
touch at [support.newrelic.com](http://support.newrelic.com) and let us know!
