# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Instrumentation
    class StackProfProfile < Instrumentor
      platforms :mri_21

      def self.setup
        require 'tmpdir'
        require 'stackprof'
      end

      def before(test, test_name)
        @profile_dir = Dir.mktmpdir('stackprof-profile')
        @profile_path = File.join(@profile_dir, "profile.dump")
        StackProf.start
      end

      def after(test, test_name)
        StackProf.stop
        report = StackProf::Report.new(StackProf.results)
        output_profile_path = artifact_path(test, test_name, "dot")
        File.open(output_profile_path, "w") do |f|
          report.print_graphviz(nil, f)
        end
        @artifacts << output_profile_path
        FileUtils.remove_entry_secure(@profile_dir)
      end
    end
  end
end
