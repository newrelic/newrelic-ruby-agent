require 'new_relic/control/frameworks/rails3'
require 'new_relic/rack/error_collector'
module NewRelic
  class Control
    module Frameworks
      class Rails4 < NewRelic::Control::Frameworks::Rails3
        def rails_gem_list
          Bundler.rubygems.all_specs.map do |gem|
            "#{gem.name} (#{gem.version})"
          end
        end

        def add_error_collector_middleware
          # rails_config.middleware.use NewRelic::Rack::ErrorCollector
        end

        def append_plugin_list
          # Rails 4 does not allow plugins
        end
      end
    end
  end
end
