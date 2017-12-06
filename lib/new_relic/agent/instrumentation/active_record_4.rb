# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_prepend'
require 'new_relic/agent/instrumentation/active_record_subscriber'
require 'new_relic/agent/prepend_supportability'

DependencyDetection.defer do
  named :active_record_4

  depends_on do
    defined?(::ActiveRecord) && defined?(::ActiveRecord::Base) &&
      defined?(::ActiveRecord::VERSION) &&
      ::ActiveRecord::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing ActiveRecord 4 instrumentation'
  end

  executes do
    ActiveSupport::Notifications.subscribe('sql.active_record',
      NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new)

    ActiveSupport.on_load(:active_record) do
      ::NewRelic::Agent::PrependSupportability.record_metrics_for(::ActiveRecord::Base, ::ActiveRecord::Relation)

      if NewRelic::Agent.config[:prepend_active_record_instrumentation]
        ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions
        ::ActiveRecord::Relation.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::RelationExtensions
      else
        ::NewRelic::Agent::Instrumentation::ActiveRecordHelper.instrument_additional_methods
      end
    end
  end
end
