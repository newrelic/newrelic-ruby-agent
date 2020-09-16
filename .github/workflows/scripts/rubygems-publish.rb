require 'rotp'
require 'base32'

version = ENV["VERSION"]
mfa_identifier = Base32.encode ENV["RUBY_GEMS_MFA_KEY"]
totp = ROTP::TOTP.new(mfa_identifier)

puts "Publshing the newrelic_rpm-#{version}.gem file..."
cmd = "gem push --otp #{totp.now} newrelic_rpm-#{version}.gem"
puts "executing: #{cmd}"
puts `#{cmd}`

puts "Publshing the newrelic-infinite_tracing-#{version}.gem file..."
cmd = "gem push --otp #{totp.now} newrelic-infinite_tracing-#{version}.gem"
puts "executing: #{cmd}"
puts `#{cmd}`
