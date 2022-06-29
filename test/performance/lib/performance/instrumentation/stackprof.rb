# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  module Instrumentation
    class StackProfProfile < Instrumentor
      platforms :mri_22, :mri_23, :mri_24, :mri_25, :mri_26, :mri_27, :mri_30, :mri_31

      def self.setup
        require 'tmpdir'
        require 'stackprof'
      end

      def mode
        :wall
      end

      def before(test, test_name)
        StackProf.start(:mode => mode)
      end

      def after(test, test_name)
        StackProf.stop

        output_dump_path = artifact_path(test, test_name, "dump")
        StackProf.results(output_dump_path)
        @artifacts << output_dump_path

        results = Marshal.load(File.read(output_dump_path))
        output_dot_path = artifact_path(test, test_name, "dot")
        report = StackProf::Report.new(results)
        File.open(output_dot_path, "w") do |f|
          report.print_graphviz({}, f)
        end
        @artifacts << output_dot_path
      end
    end

    class StackProfAllocationProfile < StackProfProfile
      def mode
        :object
      end
    end
  end
end
