# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hometown/version'

Gem::Specification.new do |spec|
  spec.name          = "hometown"
  spec.version       = Hometown::VERSION
  spec.authors       = ["Jason R. Clark"]
  spec.email         = ["jason@jasonrclark.com"]
  spec.summary       = %q{Track object creation}
  spec.description   = %q{Track object creation to stamp out pesky leaks.}
  spec.homepage      = "http://github.com/jasonrclark/hometown"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler",   "~> 1.6"
  spec.add_development_dependency "coveralls", "~> 0.7"
  spec.add_development_dependency "rake",      "~> 10.2"
  spec.add_development_dependency "minitest",  "~> 5.3"
  spec.add_development_dependency "pry",       "~> 0.9"
  spec.add_development_dependency "pry-nav",   "~> 0.2"
  spec.add_development_dependency "guard",     "~> 2.6"
  spec.add_development_dependency "guard-minitest", "~> 1.3"
end
