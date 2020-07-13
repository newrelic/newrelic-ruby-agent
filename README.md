[![Community Project header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Project.png)](https://opensource.newrelic.com/oss-category/#community-project)

# New Relic Ruby Agent

New Relic is a performance management system, developed by
New Relic, Inc (https://newrelic.com).  It provides you with deep
information about the performance of your Rails or Ruby
application as it runs in production and transmits them to
newrelic.com where you can monitor them in real time. The New Relic
Ruby Agent is dual-purposed as a either a Gem or a Rails plugin,
hosted on [github](https://github.com/newrelic/newrelic-ruby-agent/tree/main).

The New Relic Ruby agent is released approximately ten to twelve times a year.

## Supported Environments

An up-to-date list of Ruby versions and frameworks for the latest agent
can be found on [our docs site](http://docs.newrelic.com/docs/ruby/supported-frameworks).

You can also monitor non-web applications. Refer to the "Other
Environments" section under "Getting Started".

## Installing and Using

### Quick Start

For using with Bundler, add the Ruby Agent to your project's Gemfile.

```ruby
gem 'newrelic_rpm'
```

and run `bundle install` to activate the new gem.

With Bundler, install the gem with:

```bash
gem install newrelic_rpm
```

and then require the New Relic Ruby agent in your Ruby start-up chain:

```ruby
require 'newrelic_rpm'
```

Some frameworks and non-framework environments may require you to also add the following line after the above require:

```ruby
NewRelic::Agent.manual_start
```

### Complete Install Instructions

For complete documentation on Getting started with the New Relic Ruby agent, see the following links:

* [Introduction](https://docs.newrelic.com/docs/agents/ruby-agent/getting-started/introduction-new-relic-ruby)
* [Install the New Relic Ruby agent](https://docs.newrelic.com/docs/agents/ruby-agent/installation/install-new-relic-ruby-agent)
* [Configure the agent](https://docs.newrelic.com/docs/agents/ruby-agent/configuration/ruby-agent-configuration)
* [Update the agent](https://docs.newrelic.com/docs/agents/ruby-agent/installation/update-ruby-agent)
* [Rails plugin installation](https://docs.newrelic.com/docs/agents/ruby-agent/installation/ruby-agent-installation-rails-plugin)
* [GAE Flexible Environment](https://docs.newrelic.com/docs/agents/ruby-agent/installation/install-new-relic-ruby-agent-gae-flexible-environment)
* [Pure Rack Apps](http://docs.newrelic.com/docs/ruby/rack-middlewares)
* [Ruby agent and Heroku](https://docs.newrelic.com/docs/agents/ruby-agent/installation/ruby-agent-heroku)
* [Background Jobs](https://docs.newrelic.com/docs/agents/ruby-agent/background-jobs)
* [Uninstall the Ruby agent](https://docs.newrelic.com/docs/agents/ruby-agent/installation/uninstall-ruby-agent)

Refer to the [New Relic's Docs](http://newrelic.com/docs) for details on how to
monitor other web frameworks, background jobs, and daemons.

### Production Mode

When your application runs in the production environment, the New
Relic agent runs in production mode. It connects to the New Relic
service and sends deep performance data to the UI for your
analysis. To view this data, log in to http://rpm.newrelic.com.

NOTE: You must have a valid account and license key to view this data
online.  Refer to instructions in *Getting Started*.

### Recording Deploys

The Ruby Agent supports recording deployments in New Relic via a command line
tool or Capistrano recipes. For more information on these features see
[our deployment documentation](http://docs.newrelic.com/docs/ruby/recording-deployments-with-the-ruby-agent)
for more information.

## Support

New Relic hosts and moderates an online forum where customers can interact with New Relic employees as well as other customers to get help and share best practices. Like all official New Relic open source projects, there's a related Community topic in the New Relic Explorers Hub. You can find this project's topic/threads here:

https://discuss.newrelic.com/c/support-products-agents/ruby-agent

## Contributing

We encourage contributions to improve the New Relice Ruby agent! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project.
If you have any questions, or to execute our corporate CLA, required if your contribution is on behalf of a company,  please drop us an email at opensource@newrelic.com.

If you would like to contribute to this project, please review [these guidelines](./CONTRIBUTING.md).

## License
The New Relic Ruby agent is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
The New Relic Ruby agent also uses source code from third-party libraries. Full details on which libraries are used and the terms under which they are licensed can be found in the [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

## Support

You can find more detailed documentation [on our website](http://newrelic.com/docs),
and specifically in the [Ruby category](http://newrelic.com/docs/ruby).

## Thank You

Thank you, and may your application scale to infinity plus one.

Lew Cirne, Founder and CEO

New Relic, Inc.
