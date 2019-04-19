# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_subscriber'
require 'new_relic/agent/instrumentation/active_record_prepend'

DependencyDetection.defer do
  named :active_record_notifications

  depends_on do
    defined?(::ActiveRecord) && defined?(::ActiveRecord::Base) &&
      defined?(::ActiveRecord::VERSION) &&
      ::ActiveRecord::VERSION::MAJOR.to_i >= 4
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing notifications based Active Record instrumentation'
  end

  executes do
    ActiveSupport::Notifications.subscribe('sql.active_record',
      NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new)
  end

  executes do
    ActiveSupport.on_load(:active_record) do
      ::NewRelic::Agent::PrependSupportability.record_metrics_for(
          ::ActiveRecord::Base,
          ::ActiveRecord::Relation)

      # Default to .prepending, unless the ActiveRecord version is <=4 
      # **AND** the :prepend_active_record_instrumentation config is false
      if ::ActiveRecord::VERSION::MAJOR > 4 \
          || ::NewRelic::Agent.config[:prepend_active_record_instrumentation]

        ::ActiveRecord::Base.send(:prepend,
            ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions)
        ::ActiveRecord::Relation.send(:prepend,
            ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::RelationExtensions)
      else
        ::NewRelic::Agent::Instrumentation::ActiveRecordHelper.instrument_additional_methods
      end
    end
  end

  executes do
    if ::ActiveRecord::VERSION::MAJOR == 5 \
        && ::ActiveRecord::VERSION::MINOR.to_i == 1 \
        && ::ActiveRecord::VERSION::TINY.to_i >= 6

      ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions516
    end
  end
end
