# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Instrumentation
    class PerfToolsProfile < Instrumentor
      platforms :mri_19, :mri_20, :mri_21

      def self.setup
        require 'tmpdir'
        require 'perftools'
      end

      def before(test, test_name)
        @profile_dir = Dir.mktmpdir('profile')
        @profile_path = File.join(@profile_dir, "profile")
        PerfTools::CpuProfiler.start(@profile_path)
      end

      def after(test, test_name)
        PerfTools::CpuProfiler.stop
        output_profile_path = artifact_path(test, test_name, "dot")
        system("pprof.rb --dot #{@profile_path} >#{output_profile_path}")
        @artifacts << output_profile_path
        FileUtils.remove_entry_secure(@profile_dir)
      end
    end
  end
end
