module NewRelic
  class Control
    # used to contain methods to look up settings from the
    # configuration located in newrelic.yml
    module Configuration
      def apdex_t
        Agent.config[:apdex_t]
      end
    end
    include Configuration
  end
end
