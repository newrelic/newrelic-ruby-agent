require 'singleton'

# the session counter counts the number of sessions that have had recent activity
# in this application.  Recent is defined by age_out_time, which defaults to
# 5 minutes.  This may be very different from the application's real "age out'
# value for its session management, but in this case we are measuring the number
# of live users on the site, so the age out time must be a relatively small number
module Seldon::Agent
  class SessionCounter
    include Singleton
    
  private
    def initialize(age_out_time = 5.minutes)
      @age_out_time = age_out_time
      @sessions = {}
    end
    
    
  end
end