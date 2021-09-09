# -*- encoding: utf-8 -*-
# stub: debug_inspector 1.1.0 ruby lib
# stub: ext/debug_inspector/extconf.rb

Gem::Specification.new do |s|
  s.name = "debug_inspector".freeze
  s.version = "1.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/banister/debug_inspector/releases", "homepage_uri" => "https://github.com/banister/debug_inspector", "source_code_uri" => "https://github.com/banister/debug_inspector" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["John Mair (banisterfiend)".freeze]
  s.date = "2021-03-23"
  s.description = "Adds methods to RubyVM::DebugInspector to allow for inspection of backtrace frames.\n\nThe debug_inspector C extension and API were designed and built by Koichi Sasada, this project is just a gemification of his work.\n\nThis library makes use of the debug inspector API which was added to MRI 2.0.0.\nOnly works on MRI 2 and 3. Requiring it on unsupported Rubies will result in a no-op.\n\nRecommended for use only in debugging situations. Do not use this in production apps.\n".freeze
  s.email = ["jrmair@gmail.com".freeze]
  s.extensions = ["ext/debug_inspector/extconf.rb".freeze]
  s.files = ["ext/debug_inspector/extconf.rb".freeze]
  s.homepage = "https://github.com/banister/debug_inspector".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0".freeze)
  s.rubygems_version = "3.0.3".freeze
  s.summary = "A Ruby wrapper for the MRI 2.0 debug_inspector API".freeze

  s.installed_by_version = "3.0.3" if s.respond_to? :installed_by_version
end
