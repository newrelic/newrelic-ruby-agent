source 'https://rubygems.org'

group :development do
  # require 0.9.6.
  # There's problems with the test task in rake 10
  # https://github.com/jimweirich/rake/issues/144
  gem 'rake', '0.9.6'
  if RUBY_VERSION > '1.9.0'
    gem 'mocha', '~>0.13.0', :require => false
  else
    gem 'mocha', '~>0.12.0'
  end
  gem 'shoulda', '~>3.0.1'
  gem 'sdoc-helpers'
  gem 'rdoc', '>= 2.4.2'
  gem 'rails', '~>3.2.0'
  gem 'sqlite3', :platform => 'mri'
  gem 'activerecord-jdbcsqlite3-adapter', :platform => 'jruby'
  gem 'jruby-openssl', :platform => 'jruby'
end
