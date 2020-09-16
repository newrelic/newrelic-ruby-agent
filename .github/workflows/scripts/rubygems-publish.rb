require 'rotp'
require 'base32'

version = ENV["VERSION"]
mfa_identifier = Base32.encode ENV["RUBY_GEMS_MFA_KEY"]

puts "Publshing the newrelic_rpm-#{version}.gem file..."
puts `gem push --otp #{totp = ROTP::TOTP.new(mfa_identifier)} newrelic_rpm-#{version}.gem`

puts "Publshing the newrelic-infinite_tracing-#{version}.gem file..."
puts `gem push --otp #{totp = ROTP::TOTP.new(mfa_identifier)} newrelic-infinite_tracing-#{version}.gem`
