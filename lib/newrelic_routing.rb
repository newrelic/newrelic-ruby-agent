# REVIEW This is a monkey patch to inject the developer tool route into the
# parent app without requiring users to modify their routes. Of course this 
# has the effect of adding a route indiscriminantly which is frowned upon by 
# some: http://www.ruby-forum.com/topic/126316#563328
module ActionController
  module Routing
    class RouteSet
      def draw
        clear!
        map = Mapper.new(self)
        map.named_route 'newrelic_developer', '/newrelic', :controller => 'newrelic'
        yield map
        install_helpers
      end
    end
  end
end