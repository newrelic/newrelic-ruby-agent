#-*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'new_relic/version'

Gem::Specification.new do |s|
  s.name = "newrelic_rpm"
  s.version = NewRelic::VERSION::STRING
  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = [ "Jason Clark", "Sam Goldstein", "Jon Guymon", "Ben Weintraub" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.description = <<-EOS
New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on
http://github.com/newrelic/rpm/
EOS
  s.email = "support@newrelic.com"
  s.executables = [ "mongrel_rpm", "newrelic_cmd", "newrelic" ]
  s.extra_rdoc_files = [
    "CHANGELOG",
    "LICENSE",
    "README.md",
    "GUIDELINES_FOR_CONTRIBUTING.md",
    "newrelic.yml"
  ]
  s.files = `git ls-files`.split + ['lib/new_relic/build.rb']
  s.homepage = "http://www.github.com/newrelic/rpm"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "New Relic Ruby Agent"]
  s.require_paths = ["lib"]
  s.rubygems_version = Gem::VERSION
  s.summary = "New Relic Ruby Agent"

  version_count = 0
  changes = []
  File.read(File.join(File.dirname(__FILE__), 'CHANGELOG')).each_line do |line|
    if line.match(/##\s+v[\d.]+\s+##/)
      version_count += 1
    end
    break if version_count >= 2
    changes << line.chomp
  end

  post_install_message = changes.join("\n")
  post_install_message += <<'EOS'

See https://github.com/newrelic/rpm/blob/master/CHANGELOG for a full list of
changes.
EOS
  s.post_install_message = post_install_message
end
