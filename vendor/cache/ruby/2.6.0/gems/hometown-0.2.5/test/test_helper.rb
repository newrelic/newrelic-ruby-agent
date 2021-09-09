if ENV["CI"]
  require 'coveralls'
  Coveralls.wear!
end

gem 'minitest'
require 'minitest/autorun'
