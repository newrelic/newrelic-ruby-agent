# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Instrumentation
    def self.load_instrumentors
      dir = File.expand_path(File.join(File.dirname(__FILE__), 'instrumentation'))
      Dir.glob(File.join(dir, "*.rb")).each do |filename|
        require filename
      end
    end

    def self.default_instrumentors
      Instrumentor.subclasses.select do |cls|
        cls.on_by_default? && cls.supported?
      end
    end

    def self.instrumentor_class_by_name(name)
      begin
        cls = self.const_get(name)
        if cls.supported?
          cls
        else
          Performance.logger.warn("Instrumentor '#{name}' is unsupported on this platform")
          nil
        end
      rescue NameError => e
        Performance.logger.error("Failed to load instrumentor '#{name}': #{e.inspect}")
        nil
      end
    end

    class Instrumentor
      def self.inherited(cls)
        @subclasses ||= []
        @subclasses << cls
      end

      def self.subclasses
        @subclasses || []
      end

      def self.platforms(*args)
        @supported_platforms = args
      end

      def self.supported?
        (
          @supported_platforms.nil? ||
          Platform.current.match_any?(@supported_platforms)
        )
      end

      def self.on_by_default
        @on_by_default = true
      end

      def self.on_by_default?
        @on_by_default
      end

      attr_reader :artifacts

      def initialize(artifacts_dir)
        @artifacts_dir = artifacts_dir
        reset
      end

      def reset
        @artifacts = []
      end

      def pretty_name
        self.class.name.split("::").last
      end

      def artifacts_dir_for(test_case, test_name)
        path = File.join(@artifacts_dir, test_case.class.name, test_name)
        FileUtils.mkdir_p(path)
        path
      end

      def artifact_path(test_case, test_name, extension)
        File.join(artifacts_dir_for(test_case, test_name), "#{pretty_name}.#{extension}")
      end

      def before(*); end
      def after(*); end
      def results; {}; end
    end
  end
end

Performance::Instrumentation.load_instrumentors
