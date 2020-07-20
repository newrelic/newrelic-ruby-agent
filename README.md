# New Relic Ruby Agent

New Relic is a performance management system, developed by
New Relic, Inc (http://www.newrelic.com).  It provides you with deep
information about the performance of your Rails or Ruby
application as it runs in production and transmits them to
newrelic.com where you can monitor them in real time. The New Relic
Ruby Agent is dual-purposed as a either a Gem or a Rails plugin,
hosted on [github](https://github.com/newrelic/rpm/tree/master).

## Supported Environments

An up-to-date list of Ruby versions and frameworks for the latest agent
can be found on [our docs site](http://docs.newrelic.com/docs/ruby/supported-frameworks).

You can also monitor non-web applications. Refer to the "Other
Environments" section under "Getting Started".

## Contributing Code

We welcome code contributions (in the form of pull requests) from our user
community.  Before submitting a pull request please review
[these guidelines](https://github.com/newrelic/rpm/blob/master/CONTRIBUTING.md).

Following these helps us efficiently review and incorporate your contribution
and avoid breaking your code with future changes to the agent.


## Getting Started

Add the Ruby Agent to your project's Gemfile.

    gem 'newrelic_rpm'

To monitor your applications in production, create an account at
http://newrelic.com/ .  There you can
sign up for a free Lite account or one of our paid subscriptions.

Once you receive the welcome email with a license key and
`newrelic.yml` file, you can copy the `newrelic.yml` file into your app config
directory OR can generate the file manually with command:

    newrelic install --license_key="YOUR_KEY" "My application"

The initial configuration is done in the `newrelic.yml` file.  This file
is by default read from the `config` directory of the application root
and is subsequently searched for in the application root directory,
and then in a `~/.newrelic` directory.  Once you're up and running you can
enable Server Side Config and manage your newrelic configuration from the web
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

To use the Ruby Agent with a Sinatra app, add:

```ruby
require 'newrelic_rpm'
```

in your Sinatra app, below the Sinatra require directive.

Then make sure you set `RACK_ENV` to the environment corresponding to the
configuration definitions in the newrelic.yml file; e.g., development,
staging, production, etc.

#### Other Environments

You can use the Ruby Agent to monitor any Ruby application. Add:

```ruby
require 'newrelic_rpm'
```

to your startup sequence and then manually start the agent using:

```ruby
NewRelic::Agent.manual_start
```

For information about instrumenting pure Rack applications, see our
[Rack middlewares documentation](http://docs.newrelic.com/docs/ruby/rack-middlewares).

Refer to the [New Relic's Docs](http://newrelic.com/docs) for details on how to
monitor other web frameworks, background jobs, and daemons.

The Ruby Agent provides an API that allows custom instrumentation of additional
frameworks.  You can find a list of community created intrumentation plugins
(e.g. [newrelic-redis](https://github.com/evanphx/newrelic-redis)) in the
[extends_newrelic_rpm project](https://github.com/newrelic/extends_newrelic_rpm).

## Production Mode

When your application runs in the production environment, the New
Relic agent runs in production mode. It connects to the New Relic
service and sends deep performance data to the UI for your
analysis. To view this data, log in to http://rpm.newrelic.com.

NOTE: You must have a valid account and license key to view this data
online.  Refer to instructions in *Getting Started*.

## Recording Deploys

The Ruby Agent supports recording deployments in New Relic via a command line
tool or Capistrano recipes. For more information on these features see
[our deployment documentation](http://docs.newrelic.com/docs/ruby/recording-deployments-with-the-ruby-agent)
for more information.

## Support

Should you need assistance with New Relic products, you are in good hands with several [**Optional** support diagnostic tools and] support channels.

This [troubleshooting framework](https://discuss.newrelic.com/t/ruby-troubleshooting-framework-install/108685) steps you through common troubleshooting questions.

New Relic offers NRDiag, [a client-side diagnostic utility](https://docs.newrelic.com/docs/using-new-relic/cross-product-functions/troubleshooting/new-relic-diagnostics) that automatically detects common problems with New Relic agents. If NRDiag detects a problem, it suggests troubleshooting steps. NRDiag can also automatically attach troubleshooting data to a New Relic Support ticket.

If the issue has been confirmed as a bug or is a Feature request, please file a Github issue.

**Support Channels**

* [New Relic Documentation](https://docs.newrelic.com/docs/agents/ruby-agent): Comprehensive guidance for using our platform
* [New Relic Community](https://discuss.newrelic.com/c/support-products-agents/ruby-agent): The best place to engage in troubleshooting questions
* [New Relic Developer](https://developer.newrelic.com/): Resources for building a custom observability applications
* [New Relic University](https://learn.newrelic.com/): A range of online training for New Relic users of every level
* [New Relic Technical Support](https://support.newrelic.com/) 24/7/365 ticketed support. Read more about our [Technical Support Offerings](https://docs.newrelic.com/docs/licenses/license-information/general-usage-licenses/support-plan). 

## Privacy

At New Relic we take your privacy and the security of your information seriously, and are committed to protecting your information. We must emphasize the importance of not sharing personal data in public forums, and ask all users to scrub logs and diagnostic information for sensitive information, whether personal, proprietary, or otherwise.

We define “Personal Data” as any information relating to an identified or identifiable individual, including, for example, your name, phone number, post code or zip code, Device ID, IP address and email address.

Please review [New Relic’s General Data Privacy Notice](https://newrelic.com/termsandconditions/privacy) for more information.

## Thank You

Thank you, and may your application scale to infinity plus one.

Lew Cirne, Founder and CEO

New Relic, Inc.
