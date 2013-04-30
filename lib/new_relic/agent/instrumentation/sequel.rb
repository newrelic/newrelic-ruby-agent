# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

DependencyDetection.defer do
  @name = :sequel

  depends_on do
    defined?(::Sequel)
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
    !NewRelic::Agent.config[:disable_database_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sequel instrumentation'

    if Sequel::Database.respond_to?( :after_initialize )
      Sequel::Database.after_initialize do |db|
        db.extension :newrelic_instrumentation
      end
    else
      NewRelic::Agent.logger.info "Detected Sequel version %s." % [ Sequel::VERSION ]
      NewRelic::Agent.logger.info "Please see additional documentation: " +
        "https://newrelic.com/docs/ruby/sequel-instrumentation"
    end

    Sequel.synchronize do
      Sequel::DATABASES.each { |db| db.extension :newrelic_instrumentation }
    end

    Sequel::Model.plugin :newrelic_instrumentation

  end

end

