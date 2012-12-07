module NewRelic
  module Agent
    module Configuration
      MASK_DEFAULTS = {
        :'thread_profiler' =>         Proc.new { !NewRelic::Agent::ThreadProfiler.is_supported? },
        :'thread_profiler.enabled' => Proc.new { !NewRelic::Agent::ThreadProfiler.is_supported? },
      }
    end
  end
end
