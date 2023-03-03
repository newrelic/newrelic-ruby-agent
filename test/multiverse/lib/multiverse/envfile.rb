# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Multiverse
  # Reads an envfile.rb and converts it into gemfiles that can be used by
  # bundler
  class Envfile
    attr_accessor :file_path, :condition
    attr_reader :before, :after, :mode, :skip_message, :omit_collector
    attr_reader :instrumentation_permutations

    def initialize(file_path)
      self.file_path = file_path
      @instrumentation_permutations = ['chain']
      @gemfiles = []
      @mode = 'fork'
      if File.exist?(file_path)
        @text = File.read(self.file_path)
        instance_eval(@text)
      end
      @gemfiles = [''] if @gemfiles.empty?
    end

    def suite_condition(skip_message, &block)
      @skip_message = skip_message
      @condition = block
    end

    def create_gemfiles(versions)
      versions.each do |version|
        if version.is_a?(Array)
          version, first_supported_ruby_version, last_supported_ruby_version = version
          next if unsupported_ruby_version?(
            last_supported_ruby_version,
            first_supported_ruby_version
          )
        end

        version = if version&.start_with?('=')
          add_version(version.sub('= ', ''), false) # don't twiddle wakka
        else
          add_version(version)
        end

        gemfile(gem_list(version))
      end
    end

    def unsupported_ruby_version?(last_supported_ruby_version, first_supported_ruby_version)
      last_supported_ruby_version?(last_supported_ruby_version) ||
        first_supported_ruby_version?(first_supported_ruby_version)
    end

    def strip_leading_spaces(content)
      content.split("\n").map(&:strip).join("\n") << "\n" if content
    end

    def gemfile(content)
      content = strip_leading_spaces(content)
      @gemfiles.push(content) unless content.nil? || content.empty?
    end

    def ruby3_gem_sorted_set
      RUBY_VERSION >= '3.0.0' ? "gem 'sorted_set'" : ''
    end

    def omit_collector!
      @omit_collector = true
    end

    def instrumentation_methods(*args)
      @instrumentation_permutations = args.map(&:to_s)
    end

    def before_suite(&block)
      @before = block
    end

    def after_suite(&block)
      @after = block
    end

    def execute_mode(mode)
      valid_modes = %w[ fork spawn ]
      unless valid_modes.member?(mode)
        raise ArgumentError, "#{mode.inspect} is not a valid execute mode.  Valid modes: #{valid_modes.inspect}"
      end

      @mode = mode
    end

    include Enumerable
    def each(&block)
      @gemfiles.each(&block)
    end

    def [](key)
      @gemfiles[key]
    end

    def permutations
      @instrumentation_permutations.size
    end

    def size
      @gemfiles.size
    end

    def add_version(version, twiddle_wakka = true)
      return unless version

      ", '#{'~> ' if twiddle_wakka}#{version}'"
    end

    private

    def last_supported_ruby_version?(last_supported_ruby_version)
      return false if last_supported_ruby_version.nil?

      last_supported_ruby_version && RUBY_VERSION.to_f > last_supported_ruby_version
    end

    def first_supported_ruby_version?(first_supported_ruby_version)
      return false if first_supported_ruby_version.nil?

      RUBY_VERSION.to_f < first_supported_ruby_version
    end
  end
end
