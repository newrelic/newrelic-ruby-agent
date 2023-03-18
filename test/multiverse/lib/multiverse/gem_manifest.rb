#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

module Multiverse
  class GemManifest
    GEMFILE_HEADER = %q(source 'https://rubygems.org')
    LOCKFILE = 'Gemfile.lock'
    OUTPUT_FILE = "gem_manifest_#{RUBY_VERSION}.json"
    SUITES_DIR = File.expand_path('../../../suites', __FILE__)

    def initialize(args = [])
      @suite_paths = []
      @gems = {}
      @opwd = Dir.pwd
      discover_suites
    end

    def report
      process_suites
      determine_latest_versions
      deliver_output
    end

    private

    def create_lockfile(dir)
      Bundler.with_unbundled_env do
        `cd #{dir} && bundle lock --lockfile=#{File.join(dir, LOCKFILE)}`
      end
    end

    def deliver_output
      results = @gems.each_with_object({}) do |(name, versions), hash|
        hash[name] = versions.keys
        puts "#{name} => #{hash[name]}"
      end
      FileUtils.rm_f(OUTPUT_FILE)
      File.open(OUTPUT_FILE, 'w') { |f| f.print results.to_json }
      puts
      puts "Results written to #{OUTPUT_FILE}"
    end

    def determine_latest_versions
      gems_wanting_latest = @gems.select { |_name, versions| versions.key?(nil) }.keys
      gemfile_body = gems_wanting_latest.map { |name| "gem '#{name}'" }.join("\n")
      dir = Dir.mktmpdir
      File.open(File.join(dir, 'Gemfile'), 'w') do |f|
        f.puts GEMFILE_HEADER
        f.puts gemfile_body
      end
      create_lockfile(dir)
      parse_lockfile(dir)
    end

    def discover_suites
      Dir.glob(File.join(SUITES_DIR, '*')).each do |path|
        @suite_paths << path if File.directory?(path)
      end
    end

    def gems_from_gemfile_body(body, path)
      body.split("\n").each do |line|
        next if line.empty? || line.match?(/(?:^\s*(?:#|if|else|end))|newrelic_(?:rpm|prepender)/)

        if line =~ /.*gem\s+['"]([^'"]+)['"](?:,\s+['"]([^'"]+)['"])?/
          gem = Regexp.last_match(1)
          version = Regexp.last_match(2)
          @gems[gem] ||= {}
          @gems[gem][version] = 1
        else
          raise "Couldn't figure out how to parse lines from evaluating the Envfile file at #{path}!"
        end
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

    def process_lockfile_hash(hash)
      hash.each do |gem, version|
        next unless @gems.key?(gem)

        @gems[gem].delete(nil)
        @gems[gem]["latest (#{version})"] = 1
      end
    end

    def process_suites
      @suite_paths.each do |path|
        Dir.chdir(path) # needed for Envfile.new's instance_eval call
        Multiverse::Envfile.new(File.join(path, 'Envfile'), ignore_ruby_version: true).map do |body|
          gems_from_gemfile_body(body, path)
        end
      end
    ensure
      Dir.chdir(@opwd)
    end

    def verify_mode
      raise "Invalid mode '#{@mode}' - must be one of #{MODES}" unless MODES.include?(@mode)
    end
  end
end
