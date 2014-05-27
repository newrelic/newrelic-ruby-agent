# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/language_support'
require 'new_relic/agent/vm/mri_vm'
require 'new_relic/agent/vm/jruby_vm'
require 'new_relic/agent/vm/rubinius_vm'

module NewRelic
  module Agent
    module VM
      def self.snapshot
        vm.snapshot
      end

      def self.vm
        @vm ||= create_vm
      end

      def self.create_vm
        if NewRelic::LanguageSupport.using_engine?('jruby')
          JRubyVM.new
        elsif NewRelic::LanguageSupport.using_engine?('rbx')
          RubiniusVM.new
        else
          MriVM.new
        end
      end
    end
  end
end
