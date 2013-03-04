# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module MetricParser
    class ORM < NewRelic::MetricParser::MetricParser
      module Hibernate
        def self.extended(base)
          if base.segments.length == 4
            base.extend JavaParser
            def base.full_class_name
              segment_2
            end
            def base.method_name
              segment_3
            end
          end
        end
      end

      def initialize(name)
        super

        if segment_1 == "Hibernate"
          self.extend NewRelic::MetricParser::ORM::Hibernate
        end
      end
    end
  end
end
