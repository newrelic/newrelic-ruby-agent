# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
    # Args with = get split, then assigned as key + value
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
      Dir.new(SUITES_DIRECTORY).entries.each do |dir|
        full_path = File.join(SUITES_DIRECTORY, dir)

        next if dir =~ /\A\./
        next unless filter.nil? || dir.include?(filter)
        next unless File.exists?(File.join(full_path, "Envfile"))

        begin
          suite = Suite.new(full_path, opts)
          suite.execute
        rescue => e
          puts red("Error when trying to run suite in #{full_path.inspect}")
          puts
          puts "#{e.class}: #{e}"
          puts *e.backtrace
          notice_exit_status 1
        end
      end

      OutputCollector.overall_report
      exit exit_status
    end

    # run_one is used to run a suite directly in process
    # Pipe shenanigans in the typical Suite runner interferes with the debugger
    def run_one(filter="", opts={})
      dir = Dir.new(SUITES_DIRECTORY).entries.find { |d| d.include?(filter) }
      full_path = File.join(SUITES_DIRECTORY, dir)
      $stderr.reopen($stdout)
      Suite.new(full_path, opts).execute_child_environment(opts.fetch(:env, "0").to_i)
    end
  end
end
