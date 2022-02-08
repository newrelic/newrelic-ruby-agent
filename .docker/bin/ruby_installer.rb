#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'yaml'
require_relative '../lib/ruby_rails_mappings.rb'

# RubyInstall - via ruby-build, install all rubies involved with the continuous integration process
class RubyInstaller
  BLOCK_PATH = '/usr/local/antonius-block'
  OPENSSL_1DOT0_DIR = File.join(BLOCK_PATH, 'openssl1.0')
  BUNDLER_MIN_VERSION = Gem::Version.new('1.17.3')
  RUBY_INSTALL_ROOT = File.join(ENV['HOME'], '.rubies')

  def initialize(allowlist=[])
    @allowlist = allowlist
  end

  def install_missing
    return 'All desired versions appear to already be installed.' if missing_versions.empty?

    missing_versions.each do |version|
      puts "Installing Ruby #{version}..."
      install_ruby(version)
    end
  end

  private

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

  def bundler_versions_for_rails_versions(rails_versions)
    rails_versions.each_with_object([]) do |rails_version, bundler_versions|
      bundler_versions << bundler_version_hash[rails_version] if bundler_version_hash.key?(rails_version)
    end
  end

  def configure_opts(ruby_version)
    return if ruby_version =~ /jruby/

    base = "RUBY_CONFIGURE_OPTS='--enable-shared --disable-install-doc"
    return "#{base}' " unless openssl1dot0_ruby?(ruby_version) && Dir.exist?(OPENSSL_1DOT0_DIR)

    "#{base} --with-openssl-dir=#{OPENSSL_1DOT0_DIR}' "
  end

  def desired_versions
    versions_hash.keys
  end

  def gem_update_bundler(ruby_version)
    return if ruby_version =~ /jruby/
    return ruby_cmd('gem update bundler', ruby_version) if Gem::Version.new(ruby_version) >= Gem::Version.new('2.6.0')
    return unless ruby_cmd('bundle -v', ruby_version) =~ /([0-9.]+)$/

    bundler_version = Regexp.last_match(1)
    return if Gem::Version.new(bundler_version) >= BUNDLER_MIN_VERSION

    ruby_cmd("gem install bundler:#{BUNDLER_MIN_VERSION} --force", ruby_version)
  end

  def gem_update_system(ruby_version)
    return if ruby_version =~ /jruby/

    # no autoupdating RubyGems until v2.3
    if Gem::Version.new(ruby_version) >= Gem::Version.new('2.3.0')
      ruby_cmd('gem update --system', ruby_version)
    else
      ruby_cmd("gem install rubygems-update -v '<3' --no-document", ruby_version)
      ruby_cmd('update_rubygems', ruby_version)
    end
  end

  def install_ruby(version)
    run_cmd("#{configure_opts(version)}ruby-build #{version} #{installation_path(version)}")
    gem_update_system(version)
    gem_update_bundler(version)
    required_bundler_versions(version).each do |bundler_version|
      puts "Installing bundler version #{bundler_version} for Ruby version #{version}..."
      ruby_cmd("gem install bundler:#{bundler_version}", version)
    end
    File.unlink('.ruby-version') if File.exist?('.ruby-version')
  end

  def installation_path(ruby_version)
    File.join(RUBY_INSTALL_ROOT, ruby_version =~ /jruby/ ? ruby_version : "ruby-#{ruby_version}")
  end

  def installed_versions
    @installed_versions ||= Dir.glob("#{RUBY_INSTALL_ROOT}/*").map { |p| File.basename(p).sub(/^ruby-/, '') }
  end

  def missing_versions
    @missing_versions ||= (@allowlist.empty? ? desired_versions : @allowlist) - installed_versions
  end

  def openssl1dot0_ruby?(ruby_version)
    ruby_version !~ /jruby/ && Gem::Version.new(ruby_version) < Gem::Version.new('2.4.0')
  end

  def rails_versions_for_ruby_version(ruby_version)
    # note: Hash#dig requires Ruby 2.3+
    (versions_hash.dig(ruby_version, 'rails') || '').split(',')
  end

  def ruby_cmd(cmd, ruby_version)
    run_cmd("#{installation_path(ruby_version)}/bin/#{cmd}")
  end

  def required_bundler_versions(ruby_version)
    bundler_versions_for_rails_versions(rails_versions_for_ruby_version(ruby_version)).uniq
  end

  def run_cmd(cmd)
    puts cmd
    result = `#{cmd}`
    raise "Command '#{cmd}' failed." unless $?.success?

    result
  end

  def versions_hash
    @versions_hash ||= begin
      ci = YAML.load_file(CI_FILE)
      # note: Hash#dig requires Ruby 2.3+
      map_yaml = ci['jobs']['unit-tests']['steps'].detect { |hash| hash.dig('with', 'map') }['with']['map']
      versions = YAML.load(map_yaml)
    end
  end
end

if $0 == __FILE__
  RubyInstaller.new(ARGV).install_missing
end
