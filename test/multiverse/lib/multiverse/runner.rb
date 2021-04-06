# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module Multiverse
  module Runner
    extend self
    extend Color

    def exit_status
      @exit_status ||= 0
    end

    def notice_exit_status(i)
      exit_status # initialize it
      # we don't want to return exit statuses > 256 since these get converted
      # to 0
      if i != 0
        puts red("FAIL! Exited #{i}")
        @exit_status = 1
      else
        puts green("PASS. Exited #{i}")
      end
      @exit_status
    end

    # Args without a = are turned into just opts[key] = true
    # Args with = get split, then assigned as key + value. Repeats overwrite
    # Args with name= will tally up rather than overwriting
    # :suite gets ignored
    def parse_args(args)
      opts = {}
      args.each do |(k, v)|
        if v.index("name=") == 0
          parts = v.split("=")
          opts[:names] ||= []
          opts[:names] << parts.last
        elsif v.include?("=")
          parts = v.split("=")
          opts[parts.first.to_sym] = parts.last
        elsif k != :suite
          opts[v.to_sym] = true
        end
      end
      opts
    end

    def run(filter="", opts={})
      execute_suites(filter, opts) do |suite|
        suite.each_instrumentation_method do |method|
          suite.execute method
        end
      end
    end

    def prime(filter="", opts={})
      execute_suites(filter, opts) do |suite|
        suite.prime
      end
    end

    def execute_suites(filter, opts)
      Dir.new(SUITES_DIRECTORY).entries.each do |dir|
        full_path = File.join(SUITES_DIRECTORY, dir)

        next if dir =~ /\A\./
        next unless passes_filter?(dir, filter)
        next unless File.exists?(File.join(full_path, "Envfile"))

        begin
          suite = Suite.new(full_path, opts)
          yield suite
        rescue => e
          puts red("Error when trying to run suite in #{full_path.inspect}")
          puts
          puts "#{e.class}: #{e}"
          puts(*e.backtrace)
          notice_exit_status 1
        end
      end

      OutputCollector.overall_report
      exit exit_status
    end

    GROUPS = {
      "agent"         => ["bare", "config_file_loading", "deferred_instrumentation", "high_security", "no_json", "json", "marshalling", "yajl"],
      "background"    => ["delayed_job", "sidekiq"],
      "background_2"  => ["resque"],
      "database"      => ["datamapper", "mongo", "redis", "sequel"],
      "frameworks"    => ["sinatra", "padrino", "grape"],
      "httpclients"   => ["curb", "excon", "httpclient", "typhoeus", "net_http", "net_http_prepend", "httprb"],
      "rails"         => ["active_record", "rails", "rails_prepend", "activemerchant"],
      "infinite_tracing" => ["infinite_tracing"],

      "rest"          => []  # Specially handled below
    }

    # Would like to reinstate but requires investigation, see RUBY-1749
    unless RUBY_VERSION >= '2.1' and RUBY_VERSION < '2.3'
      GROUPS['background'] << 'rake'
    end

    unless RUBY_PLATFORM == "java"
      GROUPS['agent'] << 'agent_only'
    end


    def passes_filter?(dir, filter)
      return true if filter.nil?

      # Would like to reinstate but requires investigation, see RUBY-1749
      return false if dir == 'rake' and RUBY_VERSION >= '2.1' and RUBY_VERSION < '2.3'
      return false if dir == 'agent_only' and RUBY_PLATFORM == "java"

      if filter.include?("group=")
        key = filter.sub("group=", "")
        group = GROUPS[key]
        if group.nil?
          puts red("Unrecognized group '#{key}'. Stopping!")
          exit 1
        elsif group.any?
          GROUPS[key].include?(dir)
        else
          !GROUPS.values.flatten.include?(dir)
        end
      else
        dir.include?(filter)
      end
    end
  end
end
