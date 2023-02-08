# frozen_string_literal: true
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "newrelic_prepender/version"

Gem::Specification.new do |spec|
  spec.name = "newrelic_prepender"
  spec.version = NewRelicPrepender::VERSION
  spec.authors = ["Kenichi Nakamura"]
  spec.email = ["knakamura@newrelic.com"]
  spec.summary = 'test module for prepend metrics'
  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ["lib"]
  spec.metadata['rubygems_mfa_required'] = 'true'
end
