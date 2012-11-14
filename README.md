# New Relic Ruby Agent

New Relic is a performance management system, developed by
New Relic, Inc (http://www.newrelic.com).  It provides you with deep
information about the performance of your Rails or Ruby
application as it runs in production. The New Relic Ruby Agent is
dual-purposed as a either a Rails plugin or a Gem, hosted on
[github](http://github.com/newrelic/rpm/tree/master).

The New Relic Ruby Agent runs in one of two modes:

#### Production Mode

Low overhead instrumentation that captures detailed information on
your application running in production and transmits them to
newrelic.com where you can monitor them in real time.

#### Developer Mode

A Rack middleware that maps `/newrelic` to an application for showing
detailed performance metrics on a page by page basis.  Installed
automatically in Rails applications.

## Supported Environments

* Ruby 1.8.6, 1.8.7, REE, 1.9.x
* JRuby 1.6 and 1.7
* Rails 2.0 or later for Production Mode
* Rails 2.3 or later for Developer Mode
* Sinatra
* Rack

Any Rack based framework should work but may not be tested.  Install
the Ruby Agent as a gem and add the Developer Mode middleware if
desired.  Report any problems to support@newrelic.com.

You can also monitor non-web applications. Refer to the "Other
Environments" section under "Getting Started".

## Contributing Code

We welcome code contributions (in the form of pull requests) from our user
community.  Before submitting a pull request please review
[GUIDELINES_FOR_CONTRIBUTING](https://github.com/newrelic/rpm/blob/master/GUIDELINES_FOR_CONTRIBUTING.md).

Following these helps us efficiently review and incorporate your contribution
and avoid breaking your code with future changes to the agent.


## Getting Started

Install the Ruby Agent as a gem.

    gem install newrelic_rpm

Or add it to your project's Gemfile.

    gem 'newrelic_rpm'

To monitor your applications in production, create an account at
http://newrelic.com/ .  There you can
sign up for a free Lite account or one of our paid subscriptions.

Once you receive the welcome e-mail with a license key and
`newrelic.yml` file, copy the `newrelic.yml` file into your app config
directory.

The initial configuration is done in the `newrelic.yml` file.  This file
is by default read from the `config` directory of the application root
and is subsequently searched for in the application root directory,
and then in a `~/.newrelic` directory.  Once you're up and running you can
enable Server Side Config and manage your newrelic configuation from the web
UI.

#### Rails Installation

You can install the agent as a Gem:

For Bundler:

Add the following line to your Gemfile:

    gem 'newrelic_rpm'

For Rails 2.x without Bundler:

edit `environment.rb` and add to the initalizer block:

    config.gem "newrelic_rpm"

#### Sinatra Installation

To use the Ruby Agent with a Sinatra app, add

    require 'newrelic_rpm'

in your Sinatra app, below the Sinatra require directive.

Then make sure you set `RACK_ENV` to the environment corresponding to the
configuration definitions in the newrelic.yml file; e.g., development,
staging, production, etc.

To use Developer Mode in Sinatra, add `NewRelic::Rack::DeveloperMode` to
the middleware stack.  See the `config.ru` sample below.

#### Other Environments

You can use the Ruby Agent to monitor any Ruby application.  Add

    require 'newrelic_rpm'

to your startup sequence and then manually start the agent using

    NewRelic::Agent.manual_start

To instrument Rack based applications, refer to the docs in
`NewRelic::Agent::Instrumentation::Rack`.

Refer to the [New Relic's Docs](http://newrelic.com/docs) for details on how to
monitor other web frameworks, background jobs, and daemons.

The Ruby Agent provides an API that allows custom instrumentation of additional
frameworks.  You can find a list of community created intrumentation plugins
(e.g. [newrelic-redis](https://github.com/evanphx/newrelic-redis)) in the
[RPM Contrib README](https://github.com/newrelic/rpm_contrib/blob/master/README.md#new-relic-ruby-agent-plugins-seperate-projects).

## Developer Mode

When running the Developer Mode, the Ruby Agent will track the
performance of every HTTP request serviced by your application, and
store in memory this information for the last 100 HTTP transactions.

To view this performance information, including detailed SQL statement
analysis, open `/newrelic` in your web application.  For instance if
you are running mongrel or thin on port 3000, enter the following into
your browser:

    http://localhost:3000/newrelic

Developer Mode is only initialized if the `developer_mode` setting in
the newrelic.yml file is set to true.  By default, it is turned off in
all environments but `development`.

#### Developer Mode in Rails

Developer Mode is available automatically in Rails Applications based
on Rails 2.3 and later.  No additional configuration is required. When
your application starts and `developer_mode` is enabled, the Ruby
Agent injects a middleware into your Rails middleware stack.

For earlier versions of Rails that support Rack, you can use
a `config.ru` as below.

#### Developer Mode in Rack Applications

Developer Mode is available for any Rack based application such as
Sinatra by installing the NewRelic::Rack::DeveloperMode
middleware. This middleware passes all requests that do not start with
/newrelic.

Here's an example entry for Developer Mode in a `config.ru` file:

    require 'new_relic/rack/developer_mode'
    use NewRelic::Rack::DeveloperMode

## Production Mode

When your application runs in the production environment, the New
Relic agent runs in production mode. It connects to the New Relic
service and sends deep performance data to the UI for your
analysis. To view this data, log in to http://rpm.newrelic.com.

NOTE: You must have a valid account and license key to view this data
online.  Refer to instructions in *Getting Started*.


## Support

Reach out to us--and to fellow users--at
[support.newrelic.com](http://support.newrelic.com/).
There you'll find documentation, FAQs, and forums where you can submit
suggestions and discuss New Relic with staff and other users.

Also available is community support on IRC: we generally use #newrelic
on irc.freenode.net

Find a bug?  E-mail support@newrelic.com, or post it to

[support.newrelic.com](http://support.newrelic.com/).

Thank you, and may your application scale to infinity plus one.

Lew Cirne, Founder and CEO

New Relic, Inc.
