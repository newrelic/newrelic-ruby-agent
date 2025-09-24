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

    RUBY34_PLUS_GEMS = <<~NON_BUILTIN_GEMS
      gem 'base64'
      gem 'bigdecimal'
      gem 'mutex_m'
      gem 'ostruct'
    NON_BUILTIN_GEMS

    def initialize(file_path, options = {})
      self.file_path = file_path
      @instrumentation_permutations = ['chain']
      @gemfiles = []
      @mode = 'fork'
      @ignore_ruby_version = options[:ignore_ruby_version] if options.key?(:ignore_ruby_version)
      if File.exist?(file_path)
        @text = File.read(self.file_path)
        @text.gsub!('__FILE__', "'#{file_path}'")
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

        gemfile(gem_list(add_version(version)))
      end
    end

    def unsupported_ruby_version?(last_supported_ruby_version, first_supported_ruby_version)
      return false if @ignore_ruby_version

      last_supported_ruby_version?(last_supported_ruby_version) ||
        first_supported_ruby_version?(first_supported_ruby_version)
    end

    def strip_leading_spaces(content)
      content.split("\n").map(&:strip).join("\n") << "\n" if content
    end

    def gemfile(content)
      content = strip_leading_spaces(content)
      return if content.nil? || content.empty?

      @gemfiles.push(add_ruby34_plus_gems(content))
    end

    def add_ruby34_plus_gems(content)
      return content unless RUBY_VERSION.split('.')[0..1].join('.').to_f >= 3.4

      content + RUBY34_PLUS_GEMS
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
      valid_modes = %w[fork spawn]
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

    def to_ary
      @gemfiles
    end

    def permutations
      @instrumentation_permutations.size
    end

    def size
      @gemfiles.size
    end

    def add_version(version)
      return unless version || version.nil? # `nil` versions test the latest version of a gem
      return ", #{version}" unless version[0].match?(/^[><=0-9]$/) # permit git, github, path, etc. pragmas

      # If the Envfile based version starts with '>', '<', '=', '>=', or '<=',
      # then preserve that prefix when creating a Gemfile. Otherwise, twiddle
      # wakka the version (prefix the version with '~>')
      twiddle_wakka = !version.start_with?('=', '>', '<')

      ", '#{'~> ' if twiddle_wakka}#{version}'"
    end

    def serialize!
      @serialize = true
    end

    def serialize?
      @serialize
    end

    # add Rails Edge to the beginning of the array of gem versions for testing,
    # unless we're operating in a PR workflow context
    def unshift_rails_edge(gem_version_array = [])
      return if ci_for_pr?

      # Unshift Rails Edge (representing the latest GitHub primary branch
      # commit for https://github.com/rails/rails) onto the front of the
      # gem version array. This produces the following line in the generated
      # Gemfile file:
      #
      #   gem 'rails', github: 'rails'
      #
      # NOTE: Individually distributed Rails gems such as Active Record are each
      #       contained within the same 'rails' GitHub repo. For now we are not
      #       too concerned with cloning the entire Rails repo despite only
      #       wanting to test one gem.
      #
      # NOTE: The Rails Edge version is not tested unless the Ruby version in
      #       play is greater than or equal to (>=) the version number at the
      #       end of the unshifted inner array
      gem_version_array.unshift(["github: 'rails'", 3.2])
    end

    # are we running in a CI context intended for PR approvals?
    def ci_for_pr?
      ENV['CI_FOR_PR'] == 'true'
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
