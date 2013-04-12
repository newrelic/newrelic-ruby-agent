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
    # (currently) Depends on the after_initialize hook added in 3.47
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
    !NewRelic::Agent.config[:disable_database_instrumentation] # &&
#     (Sequel::MAJOR > 3 || (Sequel::MAJOR == 3 && Sequel::MINOR > 46))
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sequel instrumentation'

    # Sequel::Database.after_initialize do |db|
    #   db.extension :newrelic_instrumentation
    # end

    Sequel.synchronize do
      Sequel::DATABASES.each { |db| db.extension :newrelic_instrumentation }
    end

  end

end

