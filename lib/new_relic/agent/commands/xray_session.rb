# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Commands
      class XraySession
        attr_reader :id, :active
        alias_method :active?, :active

        def initialize(raw_session)
          @id = raw_session["x_ray_id"]
        end

        def activate
          @active = true
        end

        def deactivate
          @active = false
        end
      end
    end
  end
end
