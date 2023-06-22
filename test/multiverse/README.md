# Multiverse

## Testing in a multitude of environments

Multiverse was created to solve a specific problem experienced by the Agent
team.  Not only does the New Relic Agent run in a wide variety of environments,
but its expected behavior *changes* based on the environment.  Instrumentation is
toggled on and off based on the presence of certain libraries, and some of these
libraries are incompatible with each other.  Effective testing requires us to
specify different environments for different tests; Multiverse aims to make this
painless.

## Testing and developing with Docker

This project includes optional content for leveraging Docker to perform all
unit and functional tests within containers.

See [DOCKER.md](../../DOCKER.md) for instructions
on getting started. Once the containers have been started via
`docker-compose up`, the `docker-compose exec app rake` command can be used
to replace any `rake` command found in this multiverse specific document.

## Local development setup

The multiverse suites cover a wide range of data handling software, for
storage, caching, and messaging. To test every suite, all related software
will need to be installed and all server processes will need to be up and
running.

The full list of data handling software used by the tests is as follows:

* [Elasticsearch](https://www.elastic.co/)
* [memcached](https://memcached.org)
* [MongoDB](https://www.mongodb.com)
* [MySQL](https://www.mysql.com)
* [PostgreSQL](https://www.postgresql.org)
* [RabbitMQ](https://www.rabbitmq.com)
* [Redis](https://redis.io)

If you are using [Homebrew](https://brew.sh/), then you may make use of this
project's [Brewfile](../../../Brewfile) file to automatically install all of
those applications as well as these additional dependency packages:

* [pkg-config](https://freedesktop.org/wiki/Software/pkg-config/)  
* [OpenSSL](https://www.openssl.org/)  
* [ImageMagick](https://imagemagick.org/)  

To use the project [Brewfile](../../../Brewfile) file, run the following from
the root of the project git clone where the file resides:

```shell
brew bundle
```

The [Brewfile](../../../Brewfile) file will cause all of the following
Homebrew services to be installed:

* `elasticsearch`
* `memcached`
* `mongodb-community`
* `mysql`
* `postgresql`
* `rabbitmq`
* `redis`

To start or stop a service, run the following from anywhere:

```shell
brew services start <SERVICE_NAME>
brew services stop <SERVICE_NAME>

# for example:
brew services start redis
brew services stop redis
```

Or to start or stop ALL Homebrew installed services at once, use `--all`:

```shell
brew services --all start
brew services --all stop
```

Once all of the services are up and running, all multiverse suites can be
tested. If fewer than all of the services are running, then skip to the
[Running Specific Tests and Environments](#running-specific-tests-and-environments)
section to only run a subset of the available test suites.


## Getting started

You can invoke this via rake

    rake test:multiverse

The first time you run this command on a new Ruby installation, it will take quite a long time (up to 1 hour). This is because bundler must download and install each tested version of each 3rd-party dependency. After the first run through, almost all external gem dependencies will be cached, so things won't take as long.

## Running Specific Tests and Environments

Multiverse tests live in the test/multiverse directory and are organized into 'suites'. Generally speaking, a suite is a group of tests that share a common 3rd-party dependency (or set of dependencies). You can run one or more specific suites by providing a comma delimited list of suite names as parameters to the rake task:

    rake 'test:multiverse[agent_only]'
    # or
    rake 'test:multiverse[rails,net_http]'

You can pass these additional parameters to the test:multiverse rake task to control how tests are run:

- `name=` only tests with names matching string will be executed
- `env=` only the Nth environment will be executed (may be specified multiple times)
- `file=` only tests in specified file will be executed
    NOTE: the given string will be fuzzily matched against relative paths below the suite name
          ex: "file=instrumentation" to match `test/multiverse/suites/redis/redis_instrumentation_test.rb`
- `method=` only tests for the specified method ("chain" or "prepend") will be executed
- `debug` environments for each suite will be executed in serial rather than parallel (the default), and the pry gem will be automatically included, so that you can use it to help debug tests.

```
rake 'test:multiverse[agent_only,name=test_resets_event_report_period_on_reconnect,env=0,debug]'
```


### Cleanup
Occasionally, it may be necessary to clean up your environment when migration scripts change or Gemfile lock files get out of sync.  Similar to Rails' `rake assets:clobber`, multiverse has a clobber task that will drop all multiverse databases in MySQL and remove all Gemfile.* and Gemfile.*.lock files housed under test/multiverse/suites/**

    rake test:multiverse:clobber

## Adding a test suite

To add tests add a directory to the `suites` directory.  This directory should
contain at least two files.

### Envfile

The Envfile is a meta gem file.  It allows you to specify one or more gemset
that the tests in this directory should be run against.  For example:

```ruby
gemfile <<~GEMFILE
  gem "rails", "~>6.1.0"
GEMFILE

gemfile <<~GEMFILE
  gem "rails", "~>6.0.0"
GEMFILE
```

This will run these tests against 2 environments, one running rails 6.1, the
other running rails 6.0.

New Relic is automatically included in the environment.  Specifying it in the
Envfile will trigger an error.  You can override where newrelic is loaded from
using two environment variables.

The default gemfile line is

```ruby
gem 'newrelic_rpm', path: '../../../ruby_agent'
```

`ENV['NEWRELIC_GEMFILE_LINE']` will specify the full line for the gemfile

`ENV['NEWRELIC_GEM_PATH']` will override the `:path` option in the default line.

To force a suite to serialize its tests instead of running them in parallel,
place this line somewhere within `Envfile`:

```ruby
serialize!
```

Each `Minitest::Test` class defined by a suite in a `*_test.rb` file will
perform prep work before each and every individual test if the class specifies
a `setup` instance method. To perform a "before all" or "setup once" type of
operation that is only executed once before all unit tests are invoked, there
are 2 options:

- Option 1 for smaller prep: In `Envfile`, declare a `before_suite` block:

```ruby
# Envfile
before_suite do
  complex_prep_operation_to_be_ran_once
end
```

- Option 2 for larger prep: In the suite directory, create a `before_suite.rb`
file:

```ruby
# before_suite.rb
complex_prep_operation_to_be_ran_once
```


### Test files

All files in a test suite directory (`test/multiverse/suites/*`) that end with
`_test.rb` will be executed as test files. These should use Minitest.

For example:

    class ATest < Minitest::Test
      def test_json_is_loaded
        assert JSON
      end

      def test_haml_is_not_loaded
        assert !defined?(Haml)
      end
    end


## Troubleshooting

### mysql2 gem bundling errors

On macOS, you may encounter the following error from any of the test suites
that involve the `mysql2` Rubygem.

```shell
ERROR:  Error installing mysql2:
    ERROR: Failed to build gem native extension.
```

If you encounter this, try pointing Bundler to your OpenSSL installation's `opt`
directory. If you installed OpenSSL via Homebrew, this location will be
`<HOMEBREW_PREFIX>/opt/openssl`. To obtain your Homebrew installation's prefix
path, run `brew --prefix`.

For example, if `brew --prefix` returns `/usr/local`, then the OpenSSL `opt`
path will be `/usr/local/opt/openssl`.

Once you know the `opt` path for OpenSSL, inform Bundler of this with the
following command:

```shell
bundle config --local build.mysql2 --with-opt-dir=<THE_OPT_PATH>

# for example:
bundle config --local build.mysql2 --with-opt-dir=/usr/local/opt/openssl
```

This will create or update the `.bundle/config` file in the root of the
git repo for the project. Once the `.bundle` directory exists, it will need to
be copied to every multiverse suite directory that is failing due to the
error.

For example, if the `active_record` test suite is failing:

```shell
cp -r .bundle test/multiverse/suites/active_record/
```
