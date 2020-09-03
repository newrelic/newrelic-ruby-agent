require 'rotp'

api_key = ARGV[0]
totp = ROTP::TOTP.new(api_key)
p "#{totp.now}"
