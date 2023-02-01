# Unit Tests

## Getting Started

We use Minitest for the Ruby agent.  The following command runs the unit tests without Rails:

    bundle exec rake test


## Super Easy Testing Setup

There is a script in test/script/run_tests that makes it easy to run the unit, env, and multiverse tests.

Examples

    ./test/script/run_tests -u          # unit tests
    ./test/script/run_tests -e 61       # env tests running rails61
    ./test/script/run_tests -m rake     # multiverse tests running rake in all envs and prepend/chain
    ./test/script/run_tests -q rake     # multiverse tests running rake only env 0 and prepend

If you set up shell alias for these, it will make it super convenient to run

add these aliases in ~/.bash_profile (or ~/.zshenv, depending on what shell you use)

    alias bert="./test/script/run_tests -u"
    alias bere="./test/script/run_tests -e"
    alias berm="./test/script/run_tests -m"
    alias bermq="./test/script/run_tests -q"
    alias ber="./test/script/run_tests"

Then you'll be able to run the tests super easy like

    bert # run all unit tests
    bere 61 # run env tests for rails 6.1    
    berm rake # run all rake multiverse suites
    bermq rake # run multiverse rake env=0 method=prepend
    ber -h # explains all the args for each option


## Running Tests in a Rails Environment

You can run against a specific Rails version only by passing the version name (which should match the name of a subdirectory in test/environments) as an argument to the test:env rake task, like this:

    bundle exec rake 'test:env[rails51]'

In CI, these unit tests are run against all supported major.minor versions of Rails (as well as with Rails absent entirely). The test/environments directory contains dummy Rails apps for each supported Rails versions. You can also locally run tests against all versions of Rails supported by your current Ruby version with:

    bundle exec rake test:env



## Running Specific Tests

These env variables work for both the unit tests and env tests.

Running a specific test file

    TEST="path/to/test_file_you_want_to_run.rb" bundle exec rake test


Running a specific test by name

    TESTOPTS="--name=test_name_of_test_to_run"  bundle exec rake test


You can also specify both

    TEST="path/to/test_file_you_want_to_run.rb" TESTOPTS="--name=test_name_of_test_to_run" bundle exec rake test


## Specify a seed

If you're running into intermittent failures that seem to be related to the order tests are run in, you can specify a seed to the randomization

    TESTOPTS="--seed=12345"  bundle exec rake test


## Multiverse

To run a multiverse suite

    bundle exec rake test:multiverse[suite_name]

More detailed multiverse information available in the [multiverse readme](./multiverse/README.md)





## Other Ways To Do Things

### Unit Tests Only - Specify File and Test Name
This doesn't work for the env tests, but this is also an option when running just the unit tests.

You can also run a single unit test file like this:

    bundle exec ruby test/new_relic/agent_test.rb

And to run a single test within that file (note that when using the -n argument, you can either supply the entire test name as a string or a partial name as a regex):

    bundle exec ruby test/new_relic/agent_test.rb -n /test_shutdown/


### Env Tests Only - Specify File

The file environment variable can be added to the test:env invocation to run a specific unit file.  It can be exact file name, or a wildcard pattern.  Multiple file patterns can be specified by separating with a comma with no spaces surrounding:

    file=test/new_relic/agent/distributed_tracing/* bundle exec rake 'test:env[rails60]'  # everything in this folder
    file=test/new_relic/agent/tracer_state_test.rb bundle exec rake 'test:env[rails60]'   # single file
    file=test/new_relic/agent/*_test.rb  bundle exec rake 'test:env[rails60]'             # all *_test.rb files in this folder
    file=test/new_relic/agent/distributed_tracing/*,test/new_relic/agent/datastores/* bundle exec rake 'test:env[rails60]' # all files in two folders
