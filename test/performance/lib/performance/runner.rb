# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'socket'

module Performance
  class Runner
    attr_reader :instrumentors

    DEFAULTS = {
      :instrumentors    => [],
      :inline           => false,
      :iterations       => nil,
      :reporter_classes => ['ConsoleReporter'],
      :brief            => false,
      :tags             => {},
      :dir              => File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'suites')),
      :agent_path       => ENV['AGENT_PATH'] || File.join(File.dirname(__FILE__), '..', '..', '..', '..')
    }

    def initialize(options={})
      @options = DEFAULTS.merge(options)
      create_instrumentors(options[:instrumentors] || [])
      load_test_files(@options[:dir])
      @reporter_classes = @options[:reporter_classes].map { |cls| Performance.const_get(cls) }
      @hostname = Socket.gethostname
    end

    def artifacts_base_dir
      File.expand_path(File.join('.', 'artifacts'))
    end

    def create_instrumentors(names)
      instrumentor_classes = names.map do |name|
        Performance::Instrumentation.instrumentor_class_by_name(name)
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
      test_case.on(:before_each) do |_test_case, name|
        print "#{name}: "
      end
      test_case.on(:after_each) do |_test_case, name, result|
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
        result.tags.merge!(
          :newrelic_rpm_version => @newrelic_rpm_version,
          :newrelic_rpm_git_sha => @newrelic_rpm_git_sha,
          :ruby_version         => RUBY_DESCRIPTION,
          :host                 => @hostname
        )
        result.tags.merge!(@options[:tags])
      end
    end

    def create_test_case(cls)
      test_case = cls.new
      test_case.target_iterations = @options[:iterations] if @options[:iterations]
      test_case.target_duration   = @options[:duration]   if @options[:duration]
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
      elsif @options[:identifier]
        _suite, method = @options[:identifier].split('#')
        methods = methods.select { |m| m == method }
      end
      methods
    end

    def newrelic_rpm_path
      File.expand_path(File.join(@options[:agent_path], 'lib'))
    end

    def load_newrelic_rpm
      unless @loaded_newrelic_rpm
        path = newrelic_rpm_path
        $:.unshift(path)
        require "newrelic_rpm"
        @newrelic_rpm_version = NewRelic::VERSION::STRING
        @newrelic_rpm_git_sha = find_newrelic_rpm_git_sha(path)
        @loaded_newrelic_rpm = true
      end
    end

    def find_newrelic_rpm_git_sha(path)
      build_file_path = File.join(path, 'new_relic', 'build.rb')
      if File.exist?(build_file_path)
        build_file_contents = File.read(build_file_path)
        return $1.strip if build_file_contents =~ /GITSHA: (.*)/
      else
        %x((cd '#{path}' && git log --pretty='%h' -n 1)).strip
      end
    end

    def run_test_subprocess(test_case, method)
      test_case_name = test_case.class.name
      test_identifier = "#{test_case_name}##{method}"
      runner_script = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'script', 'runner'))
      cmd = "#{runner_script} -T #{test_identifier} -j -q -I"
      cmd << " -A #{@options[:agent_path]}"
      cmd << " -N #{@options[:iterations]}" if @options[:iterations]
      cmd << " -d #{@options[:duration]}"   if @options[:duration]
      output = nil
      IO.popen(cmd) do |io|
        output = io.read
      end
      results = JSON.parse(output)
      result = Result.from_hash(results.first)
      result.tags.merge!(@options[:tags])
      result
    end

    def run_test_inline(test_case, method)
      begin
        load_newrelic_rpm
        GC.start
        test_case.run(method)
      rescue => e
        result = Result.new(test_case.class.name, method)
        result.exception = e
        result
      end
    end

    def run_test_case(test_case)
      methods_for_test_case(test_case).map do |method|
        if @options[:inline]
          run_test_inline(test_case, method)
        else
          run_test_subprocess(test_case, method)
        end
      end
    end

    def suites_to_run
      if @options[:identifier]
        suite, _method = @options[:identifier].split('#')
        TestCase.subclasses.select { |cls| cls.name == suite }
      elsif @options[:suite]
        TestCase.subclasses.select { |cls| @options[:suite].include?(cls.name) }
      else
        TestCase.subclasses
      end
    end

    def run_all_test_cases
      results = []
      suites_to_run.each do |cls|
        test_case = create_test_case(cls)
        results += run_test_case(test_case)
      end
      results
    end

    def run_and_report
      t0 = Time.now
      results = run_all_test_cases
      report_results(results, Time.now - t0)
    end

    def list_test_cases
      results = []
      suites_to_run.each do |cls|
        methods_for_test_case(cls.new).each do |method|
          results << [cls, method]
        end
      end
      results
    end

    def report_results(results, elapsed)
      @reporter_classes.each do |cls|
        cls.new(results, elapsed, @options).report
      end
    end
  end
end
