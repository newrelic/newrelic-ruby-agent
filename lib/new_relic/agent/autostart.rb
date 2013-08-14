# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # A singleton responsible for determining if the agent should start
    # monitoring.
    #
    # If the agent is in a monitored environment (e.g. production) it will
    # attempt to avoid starting at "inapproriate" times, for example in an IRB
    # session.  On Heroku, logs typically go to STDOUT so agent logs can spam
    # the console during interactive sessions.
    #
    # It should be possible to override Autostart logic with an explicit
    # configuration, for example the NEWRELIC_ENABLE environment variable or
    # agent_enabled key in newrelic.yml
    module Autostart
      extend self


      # The constants, execuatables (i.e. $0) and rake tasks used can be
      # configured with the config keys 'autostart.blacklisted_constants',
      # 'autostart.blacklisted_executables' and
      # 'autostart.blacklisted_rake_tasks'
      def agent_should_start?
          !blacklisted?('autostart.blacklisted_constants') { |name| constant_is_defined?(name) } &&
          !blacklisted?('autostart.blacklisted_executables') { |bin| File.basename($0) == bin } &&
          !in_blacklisted_rake_task?
      end

      # Lookup whether namespaced constants (e.g. ::Foo::Bar::Baz) are in the
      # environment.
      def constant_is_defined?(const_name)
        const_name.to_s.sub(/\A::/,'').split('::').inject(Object) do |namespace, name|
          begin
            result = namespace.const_get(name)

            # const_get looks up the inheritence chain, so if it's a class
            # in the constant make sure we found the one in our namespace.
            #
            # Can't help if the constant isn't a class...
            if result.is_a?(Module)
              expected_name = "#{namespace}::#{name}".gsub(/^Object::/, "")
              return false unless expected_name == result.to_s
            end

            result
          rescue NameError
            false
          end
        end
      end

      def blacklisted?(key, &block)
        ::NewRelic::Agent.config[key].split(/\s*,\s*/).any?(&block)
      end

      def in_blacklisted_rake_task?
        tasks = begin
            ::Rake.application.top_level_tasks
          rescue => e
            ::NewRelic::Agent.logger.debug("Not in Rake environment so skipping blacklisted_rake_tasks check: #{e}")
            []
          end
        !(tasks & ::NewRelic::Agent.config['autostart.blacklisted_rake_tasks'].split(/\s*,\s*/)).empty?
      end
    end
  end
end
