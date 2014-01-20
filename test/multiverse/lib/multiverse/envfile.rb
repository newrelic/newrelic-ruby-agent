# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Multiverse
  # Reads an envfile.rb and converts it into gemfiles that can be used by
  # bundler
  class Envfile
    attr_accessor :file_path, :condition
    attr_reader :before, :after, :mode, :skip_message, :omit_collector

    def initialize(file_path)
      self.file_path = file_path
      @gemfiles = []
      @mode = 'fork'
      if File.exist? file_path
        @text = File.read self.file_path
        instance_eval @text
      end
      @gemfiles = [''] if @gemfiles.empty?
    end

    def suite_condition(skip_message, &block)
      @skip_message = skip_message
      @condition = block
    end

    def gemfile(content)
      @gemfiles.push content
    end

    def omit_collector!
      @omit_collector = true
    end

    def before_suite(&block)
      @before = block
    end

    def after_suite(&block)
      @after = block
    end

    def execute_mode(mode)
      valid_modes = %w| fork spawn |
      unless valid_modes.member? mode
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

    def size
      @gemfiles.size
    end

  end
end
