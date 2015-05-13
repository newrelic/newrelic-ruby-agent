# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
#
# Rake task for running Ruby agent multiverse tests. This file may be required
# from third party gems. It is also used by the agent itself to run multiverse.
#
# Multiverse tests are grouped in (potentially multiverse) "suite" directories.
# These suites are found by default under ./test/multiverse. That location can
# be overridden with ENV['SUITES_DIRECTORY'].
#
# The first parameter to this task is a suite directory name to run.  If
# excluded, multiverse will run all suites it finds.
#
# Additional parameters are allowed to multiverse. Many parameters can be
# combined.
#
# Some examples:
#
#   # Runs ./test/multiverse/*
#   bundle exec rake test:multiverse
#
#   # Runs ./test/multiverse/my_gem
#   bundle exec rake test:multiverse[my_gem]
#
#   # With verbose logging and debugging via pry
#   bundle exec rake test:multiverse[my_gem,verbose,debug]
#
#   # Runs only first set of gems defined in my_gem's Envfile
#   bundle exec rake test:multiverse[my_gem,env=0]
#
#   # Runs tests matching the passed name (via Minitest's built-in filtering)
#   bundle exec rake test:multiverse[my_gem,name=MyGemTest]
#
#   # Runs with a specific test seed
#   bundle exec rake test:multiverse[my_gem,seed=1337]

namespace :test do
  desc "Run functional test suite for New Relic"
  task :multiverse, [:suite, :param1, :param2, :param3, :param4] => [] do |t, args|
    # Assumed that we're starting from the root of the gem unless already set
    ENV['SUITES_DIRECTORY'] ||= File.expand_path(File.join("test", "multiverse"))

    agent_root = File.expand_path(File.join(__FILE__, "..", "..", ".."))
    require File.expand_path(File.join(agent_root, 'test', 'multiverse', 'lib', 'multiverse', 'environment'))

    opts = Multiverse::Runner.parse_args(args)
    Multiverse::Runner.run(args.suite, opts)
  end
end
