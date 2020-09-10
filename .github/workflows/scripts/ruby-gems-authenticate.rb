require 'rotp'
require 'base32'

api_key = Base32.encode ARGV[0]
totp = ROTP::TOTP.new(api_key)
p "#{totp.now}"
