# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :sequel

  depends_on do
    defined?(::Sequel)
  end

  depends_on do
    !NewRelic::Agent.config[:disable_sequel_instrumentation] &&
    !NewRelic::Agent.config[:disable_database_instrumentation]
  end

  def supported_sequel_version?
    Sequel.const_defined?( :MAJOR ) &&
      ( Sequel::MAJOR > 3 ||
        Sequel::MAJOR == 3 && Sequel::MINOR >= 37 )
  end

  executes do
    if supported_sequel_version?

      ::NewRelic::Agent.logger.info 'Installing Sequel instrumentation'

      if Sequel::Database.respond_to?( :extension )
        Sequel::Database.extension :newrelic_instrumentation
      else
        NewRelic::Agent.logger.info "Detected Sequel version %s." % [ Sequel::VERSION ]
        NewRelic::Agent.logger.info "Please see additional documentation: " +
          "https://newrelic.com/docs/ruby/sequel-instrumentation"
      end

      Sequel.synchronize{Sequel::DATABASES.dup}.each do |db|
        db.extension :newrelic_instrumentation
      end

      Sequel::Model.plugin(:newrelic_instrumentation) if defined?(Sequel::Model)
    else

      NewRelic::Agent.logger.info "Sequel instrumentation requires at least version 3.37.0."

    end

  end

end
