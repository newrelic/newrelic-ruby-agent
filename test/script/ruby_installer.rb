#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'yaml'
require_relative '../helpers/ruby_rails_mappings.rb'

# RubyInstall - via rbenv, install all rubies involved with the continuous integration process
class RubyInstaller
  RUBY_VERSION_FILE = '.ruby-version'
  GEMFILE_LOCK_FILE = 'Gemfile.lock'

  def install_missing
    check_ruby_version_file
    missing_versions.each do |version|
      puts "Installing Ruby #{version}..."
      install_ruby(version)
    end
    restore_ruby_version_file
  end

  private

  def install_ruby(version)
    run_cmd("#{configure_opts(version)}rbenv install #{version}")
    run_cmd("rbenv local #{version}")
    gem_update_system(version)

    # Bundler requires v2.3+
    return unless version =~ /jruby/ || Gem::Version.new(version) >= Gem::Version.new('2.3.0')

    gem_update_bundler(version)
    File.unlink(GEMFILE_LOCK_FILE)
    run_cmd('bundle install')
    required_bundler_versions(version).each do |bundler_version|
      puts "Installing bundler version #{bundler_version} for Ruby version #{version}..."
      run_cmd("gem install bundler:#{bundler_version}")
    end
  end

  def check_ruby_version_file
    @original_ruby_version = File.read(RUBY_VERSION_FILE) if File.exist?(RUBY_VERSION_FILE)
    @original_gemfile_lock = File.read(GEMFILE_LOCK_FILE) if File.exist?(GEMFILE_LOCK_FILE)
  end

  def restore_ruby_version_file
    if @original_ruby_version
      File.write(RUBY_VERSION_FILE, @original_ruby_version) 
    else
      File.unlink(RUBY_VERSION_FILE)
    end
    if @original_gemfile_lock
      File.write(GEMFILE_LOCK_FILE, @original_gemfile_lock)
    else
      File.unlink(GEMFILE_LOCK_FILE)
    end
  end

  def rails_versions_for_ruby_version(ruby_version)
    (versions_hash.dig(ruby_version, 'rails') || '').split(',')
  end

  def configure_opts(ruby_version)
    return if ruby_version =~ /jruby/

    openssl1dot0_dir = File.join(ENV['HOME'], 'openssl1.0')
    return unless Gem::Version.new(ruby_version) < Gem::Version.new('2.4.0') && Dir.exist?(openssl1dot0_dir)

    "RUBY_CONFIGURE_OPTS='--with-openssl-dir=#{openssl1dot0_dir}' "
  end

  def gem_update_system(ruby_version)
    # no autoupdating RubyGems until v2.3
    return unless ruby_version =~ /jruby/ || Gem::Version.new(ruby_version) >= Gem::Version.new('2.3.0')

    run_cmd('gem update --system')
  end

  def gem_update_bundler(ruby_version)
    # Bundler is not included until v2.6
    if ruby_version !~ /jruby/ && Gem::Version.new(ruby_version) < Gem::Version.new('2.6.0')
      run_cmd('gem install bundler')
    else
      run_cmd('gem update bundler')
    end
  end

  def run_cmd(cmd)
    puts cmd
    result = `#{cmd}`
    raise "Command '#{cmd}' failed." unless $?.success?

    result
  end

  def bundler_versions_for_rails_versions(rails_versions)
    rails_versions.each_with_object([]) do |rails_version, bundler_versions|
      bundler_versions << bundler_version_hash[rails_version] if bundler_version_hash.key?(rails_version)
    end
  end

  def bundler_version_hash
    @bundler_version_hash ||= begin
      bundler_version_files.each_with_object({}) do |path, hash|
        next unless path =~ %r{/(rails\d+)/}

        hash[Regexp.last_match(1)] = File.read(path).chomp
      end
    end
  end

  def bundler_version_files
    Dir.glob(File.join(File.expand_path('..', __FILE__), '**/.bundler-version'))
  end

  def required_bundler_versions(ruby_version)
    bundler_versions_for_rails_versions(rails_versions_for_ruby_version(ruby_version)).uniq
  end

  def missing_versions
    desired_versions - installed_versions
  end

  def versions_hash
    @versions_hash ||= begin
      ci = YAML.load_file(CI_FILE)
      map_yaml = ci['jobs']['unit-tests']['steps'].detect { |hash| hash.dig('with', 'map') }['with']['map']
      versions = YAML.load(map_yaml)
    end
  end

  def desired_versions
    versions_hash.keys
  end

  def installed_versions
    @installed_versions ||= run_cmd('rbenv versions --bare').split("\n")
  end
end

if $0 == __FILE__
  RubyInstaller.new.install_missing
end
