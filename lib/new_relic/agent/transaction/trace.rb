# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Trace
        attr_reader :start_time, :root_segment
        attr_accessor :transaction_name, :uri, :guid, :xray_session_id,
                      :synthetics_resource_id, :agent_attributes,
                      :custom_attributes, :intrinsic_attributes

        def initialize(start_time)
          @start_time = start_time
          @root_segment = NewRelic::TransactionSample::Segment.new(0.0, "ROOT")
        end

        def trace_tree
          destination = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER
          [
            NewRelic::Coerce.float(self.start_time),
            {},
            {},
            self.root_segment.to_array,
            {
              'agentAttributes'  => self.agent_attributes.for_destination(destination),
              'customAttributes' => self.custom_attributes.for_destination(destination),
              'intrinsics'       => self.intrinsic_attributes.for_destination(destination)
            }
          ]
        end

        def to_collector_array(encoder)
          [
            NewRelic::Helper.time_to_millis(self.start_time),
            NewRelic::Helper.time_to_millis(self.root_segment.duration),
            NewRelic::Coerce.string(self.transaction_name),
            NewRelic::Coerce.string(self.uri),
            encoder.encode(trace_tree),
            NewRelic::Coerce.string(self.guid),
            forced?,
            NewRelic::Coerce.int_or_nil(xray_session_id),
            NewRelic::Coerce.string(self.synthetics_resource_id)
          ]
        end

        def forced?
          return true if NewRelic::Coerce.int_or_nil(xray_session_id)
          false
        end
      end
    end
  end
end
