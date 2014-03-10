# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :puma

  depends_on do
    defined?(::Puma) &&
      defined?(::Puma::Const::VERSION) &&
      NewRelic::VersionNumber.new(::Puma::Const::VERSION) > NewRelic::VersionNumber.new("2.0.0") &&
      ::Puma.respond_to?(:cli_config)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Puma cluster mode support'
  end

  executes do
    option_name = [:worker_boot, :before_worker_boot].detect {|option| Puma.cli_config.options.has_key? option }
    Puma.cli_config.options[option_name] << Proc.new do
      ::NewRelic::Agent.after_fork(:force_reconnect => true)
    end
  end
end
