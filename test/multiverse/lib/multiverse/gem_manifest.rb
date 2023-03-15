#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Multiverse
  class GemManifest
    GEMFILE_HEADER = %q(source 'https://rubygems.org')
    LOCKFILE = 'Gemfile.lock'
    SUITES_DIR = File.expand_path('../../../suites', __FILE__)

    def initialize
      @suite_paths = []
      @gems = {}
      discover_suites
    end

    def report
      go = Time.now.to_f
      @suite_paths.each do |path|
        print "Processing suite #{File.basename(path)}..."
        suite_go = Time.now.to_f
        Multiverse::Suite.new(path).environments.each do |environment|
          process_environment(environment)
        end
        suite_stop = Time.now.to_f
        elapsed = (suite_stop - suite_go).round(3)
        print "(#{elapsed} secs)\n"
      end
      stop = Time.now.to_f
      puts "Generating and parsing Gemfile.lock files took #{(stop - go).round(3)} secs total"
      puts
      puts 'Bundling the Multiverse would fetch these gems:'
      puts '-------------------------------------------------'
      @gems.sort.each do |gem, versions|
        puts "#{gem} => #{versions}"
      end
    end

    private

    def clean_environment(environment)
      environment.split("\n").each_with_object([]) do |line, arr|
        # ignore gems sourced from local paths
        arr << line unless line.match?(/:?path(?::| =>)/)
      end.join("\n")
    end

    def create_lockfile(dir)
      Bundler.with_unbundled_env do
        `cd #{dir} && bundle lock --lockfile=#{File.join(dir, LOCKFILE)}`
      end
    end

    def discover_suites
      Dir.glob(File.join(SUITES_DIR, '*')).each do |path|
        @suite_paths << path if File.directory?(path)
      end
    end

    def parse_lockfile(dir)
      content = File.read(File.join(dir, LOCKFILE))
      gem_specs = Regexp.last_match(1) if content =~ /\AGEM\n.*\n\s+specs:\n(.*?)\n\n/m
      desired_indentation = nil
      hash = gem_specs.split("\n").each_with_object({}) do |line, h|
        indentation = Regexp.last_match(1) if line =~ /^(\s+)/
        desired_indentation ||= indentation
        next unless indentation == desired_indentation

        h[Regexp.last_match(1).strip] = Regexp.last_match(2).strip if line =~ /^(.*?)\s+\((.*?)\)/
      end
      process_lockfile_hash(hash)
    end

    def process_environment(environment)
      cleaned = clean_environment(environment)
      dir = Dir.mktmpdir
      File.open(File.join(dir, 'Gemfile'), 'w') do |f|
        f.puts GEMFILE_HEADER
        f.puts cleaned
      end
      create_lockfile(dir)
      parse_lockfile(dir)
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    def process_lockfile_hash(hash)
      hash.each do |gem, version|
        @gems[gem] ||= []
        @gems[gem] << version unless @gems[gem].include?(version)
      end
    end
  end
end
