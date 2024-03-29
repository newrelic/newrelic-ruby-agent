# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'optparse'
require 'rubygems'
require 'json'

module Performance
  class Options
    def self.parse
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"

        opts.on('-P', '--profile', 'Do profiling around each test') do
          best_profiling_instrumentor = [
            Performance::Instrumentation::StackProfProfile,
            Performance::Instrumentation::PerfToolsProfile
          ].find(&:supported?)

          if best_profiling_instrumentor
            options[:inline] = true
            options[:instrumentors] = [best_profiling_instrumentor.to_s]
          else
            Performance.logger.warn('Could not find a supported instrumentor for profiling.')
          end
        end

        opts.on('-a', '--profile-alloc', 'Do profiling around each test for object allocations') do
          options[:inline] = true
          options[:instrumentors] = [Performance::Instrumentation::StackProfAllocationProfile.to_s]
        end

        opts.on('-l', '--list', 'List all available suites and tests') do
          options[:list] = true
        end

        opts.on('-s', '--suite=NAME', 'Filter test suites to run (allows comma separated list)') do |name|
          options[:suite] ||= []
          options[:suite].concat(name.split(','))
        end

        opts.on('-n', '--name=NAME', 'Filter tests to those matching NAME') do |name|
          options[:name] = name
        end

        opts.on('-B', '--baseline', 'Save results as a baseline') do |b|
          options[:reporter_classes] = ['BaselineSaveReporter']
        end

        opts.on('-C', '--compare', 'Compare results to a saved baseline') do |c|
          options[:reporter_classes] = ['BaselineCompareReporter']
        end

        opts.on('-N', '--iterations=NUM',
          'Set a fixed number of iterations for each test.',
          'Overrides the -d / --duration option.') do |iterations|
          options[:iterations] = iterations.to_i
        end

        opts.on('-d', '--duration=TIME',
          'Run each test for TIME seconds. Defaults to 5s.') do |duration|
          options[:duration] = duration.to_f
        end

        opts.on('-I', '--inline', 'Run tests inline - do not isolate each test into a sub-invocation') do |i|
          options[:inline] = true
        end

        opts.on('-j', '--json', 'Produce JSON output') do |q|
          options[:reporter_classes] = ['JSONReporter']
        end

        opts.on('-R', '--reporters=NAMES', 'Use the specified reporters (comma-separated list of class names)') do |reporter_names|
          reporter_names = reporter_names.split(',')
          options[:reporter_classes] = reporter_names
        end

        opts.on('-r', '--randomize', 'Randomize test order') do |r|
          options[:randomize] = r
        end

        opts.on('-b', '--brief', "Don't print out details for each test, just the elapsed time") do |b|
          options[:brief] = b
        end

        opts.on('-T', '--test=NAME', 'Run one specific test, identified by <suite name>#<test_name>') do |identifier|
          options[:identifier] = identifier
        end

        opts.on('-i', '--instrumentor=NAME', 'Use the named instrumentor') do |name|
          options[:instrumentors] = [name]
        end

        opts.on('-q', '--quiet', 'Disable diagnostic logging') do
          Performance.log_path = '/dev/null'
        end

        opts.on('-L', '--log=PATH', 'Log diagnostic information to PATH') do |log_path|
          Performance.log_path = log_path
        end

        opts.on('-A', '--agent=PATH', 'Run tests against the copy of the agent at PATH') do |path|
          options[:agent_path] = path
        end

        opts.on('-m', '--metadata=METADATA', "Attach metadata to the run. Format: 'key:value'. May be specified multiple times.") do |tag_string|
          key, value = tag_string.split(':', 2)
          options[:tags] ||= {}
          options[:tags][key] = value
        end

        opts.on('-M', '--markdown', 'Format the tabular output in Markdown') do
          options[:markdown] = true
        end
      end
      parser.parse!
      options
    end
  end
end
