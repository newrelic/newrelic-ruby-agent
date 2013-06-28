# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'socket'

module Performance
  class Runner
    attr_reader :instrumentors

    DEFAULTS = {
      :instrumentors  => [],
      :fork           => Process.respond_to?(:fork),
      :iterations     => 10000,
      :reporter_class => 'ConsoleReporter',
      :brief          => false
    }

    def initialize(options={})
      @options = DEFAULTS.merge(options)
      create_instrumentors(options[:instrumentors] || [])
      load_test_files(@options[:dir])
      @reporter_class = Performance.const_get(@options[:reporter_class])
      @hostname = Socket.gethostname
    end

    def artifacts_base_dir
      File.expand_path(File.join('.', 'artifacts'))
    end

    def create_instrumentors(names)
      instrumentor_classes = names.map do |name|
        begin
          cls = Performance::Instrumentation.const_get(name)
          if cls.supported?
            cls
          else
            $stderr.puts "Skipping requested instrumentor '#{name}' because it is unsupported on this platform"
            nil
          end
        rescue NameError => e
          $stderr.puts "Failed to load instrumentor '#{name}': #{e.inspect}"
          nil
        end
      end.compact

      instrumentor_classes |= Instrumentation.default_instrumentors

      @instrumentors = []
      instrumentor_classes.each do |cls|
        cls.setup if cls.respond_to?(:setup)
        @instrumentors << cls.new(artifacts_base_dir)
      end
    end

    def load_test_files(dir)
      Dir.glob(File.join(dir, "**", "*.rb")).each do |filename|
        require filename
      end
    end

    def add_progress_callbacks(test_case)
      test_case.on(:before_each) do |test_case, name|
        print "#{name}: "
      end
      test_case.on(:after_each) do |test_case, name, result|
        print "#{result.elapsed} s\n"
      end
    end

    def add_instrumentor_callbacks(test_case)
      test_case.on(:before_each) do |test, test_name|
        instrumentors.each do |i|
          i.reset
          i.before(test, test_name)
        end
      end
      test_case.on(:after_each) do |test, test_name, result|
        instrumentors.reverse.each { |i| i.after(test, test_name) }
        instrumentors.each do |i|
          result.measurements.merge!(i.results)
          result.artifacts.concat(i.artifacts)
        end
      end
    end

    def add_metadata_callbacks(test_case)
      test_case.on(:after_each) do |test, test_name, result|
        result.metadata.merge!(
          :newrelic_rpm_version => @newrelic_rpm_version,
          :newrelic_rpm_git_sha => @newrelic_rpm_git_sha,
          :ruby_version         => RUBY_DESCRIPTION,
          :host                 => @hostname
        )
      end
    end

    def create_test_case(cls)
      test_case = cls.new
      test_case.iterations = @options[:iterations]
      add_progress_callbacks(test_case) if @options[:progress]
      add_instrumentor_callbacks(test_case)
      add_metadata_callbacks(test_case)
      test_case
    end

    def methods_for_test_case(test_case)
      methods = test_case.runnable_test_methods
      methods = methods.shuffle if @options[:randomize]
      if @options[:name]
        filter = Regexp.new(@options[:name])
        methods = methods.select { |m| m.match(filter) }
      end
      methods
    end

    def newrelic_rpm_path
      if ENV['NEWRELIC_RPM_PATH']
        File.expand_path(ENV['NEWRELIC_RPM_PATH'])
      else
        File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib'))
      end
    end

    def load_newrelic_rpm
      unless @loaded_newrelic_rpm
        path = newrelic_rpm_path
        $: << path
        require "newrelic_rpm"
        @newrelic_rpm_version = NewRelic::VERSION::STRING
        @newrelic_rpm_git_sha = %x((cd '#{path}' && git log --pretty='%h' -n 1)).strip
        @loaded_newrelic_rpm = true
      end
    end

    def with_fork(&blk)
      if @options[:fork]
        rd, wr = IO.pipe
        Process.fork do
          load_newrelic_rpm
          rd.close
          result = blk.call
          wr.write(Marshal.dump(result))
        end
        wr.close
        result = Marshal.load(rd.read)
        rd.close
        result
      else
        load_newrelic_rpm
        blk.call
      end
    end

    def run_test_case(test_case)
      methods_for_test_case(test_case).map do |method|
        with_fork do
          test_case.run(method)
        end
      end
    end

    def run_all_test_cases
      results = []
      TestCase.subclasses.each do |cls|
        test_case = create_test_case(cls)
        results += run_test_case(test_case)
      end
      results
    end

    def report_results(results, elapsed)
      @reporter_class.new(results, elapsed, @options).report
    end
  end
end
