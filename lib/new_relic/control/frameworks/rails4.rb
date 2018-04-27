# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/control/frameworks/rails3'

module NewRelic
  class Control
    module Frameworks
      class Rails4 < NewRelic::Control::Frameworks::Rails3
        def rails_gem_list
          Bundler.rubygems.all_specs.map do |gem|
            "#{gem.name} (#{gem.version})"
          end
        end

        def append_plugin_list
          # Rails 4 does not allow plugins
        end
      end
    end
  end
end
