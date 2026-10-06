# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::LanguageSupport.can_fork?

  class ParallelPipeInheritanceTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent

    def test_workers_do_not_inherit_write_ends_of_sibling_channels
      open_sibling_write_ends = Parallel.map([1, 2, 3], in_processes: 3) do |_|
        own_channel_id = NewRelic::Agent.agent.service.channel_id
        NewRelic::Agent::PipeChannelManager.channels.count do |id, pipe|
          id != own_channel_id && !pipe.in.closed?
        end
      end

      assert_equal [0, 0, 0], open_sibling_write_ends
    end
  end
end
