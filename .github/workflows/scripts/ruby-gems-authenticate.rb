require 'rotp'
require 'base32'

mfa_identifier = Base32.encode ENV["RUBY_GEMS_MFA_KEY"]
totp = ROTP::TOTP.new(mfa_identifier)
print totp.now
