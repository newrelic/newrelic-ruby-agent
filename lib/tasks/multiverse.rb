# This rake task is intended for 3rd party extension gems to pull in multiverse
# capabilities for testing. It is not used by the agent itself for loading.
#
# Multiverse tests are expected under a test/multiverse/<GEM-NAME> directory
# To override this, you can set the ENV['SUITES_DIRECTORY'] before invoking
# this task.

namespace :test do
  desc "Run functional test suite for New Relic"
  task :multiverse, [:suite, :param1, :param2, :param3, :param4] => [] do |t, args|
    # Assumed that we're starting from the root of the gem
    ENV['SUITES_DIRECTORY'] ||= File.expand_path(File.join("test", "multiverse"))

    agent_root = File.expand_path(File.join(__FILE__, "..", "..", ".."))
    require File.expand_path(File.join(agent_root, 'test', 'multiverse', 'lib', 'multiverse', 'environment'))

    opts = Multiverse::Runner.parse_args(args)
    Multiverse::Runner.run(args.suite, opts)
  end
end
