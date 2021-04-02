# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require File.expand_path '../../data_container_tests', __FILE__

module NewRelic::Agent
  class TransactionSamplerTest < Minitest::Test

    module MockGCStats

      def time
        return 0 if @@values.empty?
        raise "too many calls" if @@index >= @@values.size
        @@curtime ||= 0
        @@curtime += (@@values[@@index] * 1e09).to_i
        @@index += 1
        @@curtime
      end

      def self.mock_values= array
        @@values = array
        @@index = 0
      end

    end

    def setup
      Tracer.clear_state
      @state = Tracer.state
      agent = NewRelic::Agent.instance
      stats_engine = StatsEngine.new
      agent.stubs(:stats_engine).returns(stats_engine)
      @sampler = TransactionSampler.new
      @old_sampler = agent.transaction_sampler
      agent.instance_variable_set(:@transaction_sampler, @sampler)
      @test_config = { :'transaction_tracer.enabled' => true }
      NewRelic::Agent.config.add_config_for_testing(@test_config)

      attributes = Attributes.new(agent.attribute_filter)
      @txn = stub('txn',
                  :best_name => '/path',
                  :request_path => '/request_path',
                  :guid => 'a guid',
                  :ignore_trace? => false,
                  :cat_trip_id => '',
                  :cat_path_hash => '',
                  :is_synthetics_request? => false,
                  :filtered_params => {},
                  :attributes => attributes
                 )
    end

    def teardown
      super
      Tracer.clear_state
      NewRelic::Agent.config.remove_config(@test_config)
      NewRelic::Agent.agent.instance_variable_set(:@transaction_sampler, @old_sampler)
    end

    # Helpers for DataContainerTests

    def create_container
      @sampler
    end

    def populate_container(sampler, n)
      n.times do |i|
        sample = sample_with(:duration => 1, :transaction_name => "t#{i}", :synthetics_resource_id => 1)
        @sampler.store_sample(sample)
      end
    end

    include NewRelic::DataContainerTests

    # Tests

    def test_captures_correct_transaction_duration
      nr_freeze_time
      in_transaction do |txn|
        advance_time(10.0)
      end

      assert_equal(10.0, @sampler.last_sample.duration)
    end

    def test_on_finishing_transaction_passes_guid_along
      in_transaction do |txn|
        txn.stubs(:guid).returns('a guid')
      end

      assert_equal('a guid', @sampler.last_sample.guid)
    end

    def test_records_cpu_time_on_transaction_samples
      in_transaction do |txn|
        txn.stubs(:cpu_burn).returns(42)
      end

      assert_equal(42, attributes_for(@sampler.last_sample, :intrinsic)[:cpu_time])
    end

    def test_harvest_when_disabled
      with_config(:'transaction_tracer.enabled' => false) do
        assert_equal([], @sampler.harvest!)
      end
    end

    def test_harvest_defaults
      # making sure the sampler clears out the old samples
      @sampler.instance_eval do
        @last_sample = 'a sample'
      end

      assert_equal([], @sampler.harvest!)

      # make sure the samples have been cleared
      assert_nil(@sampler.instance_variable_get('@last_sample'))
    end

    def test_harvest_no_data
      assert_equal([], @sampler.harvest!)
    end

    def test_add_samples_holds_onto_previous_result
      sample = sample_with(:duration => 1)
      @sampler.merge!([sample])
      assert_equal([sample], @sampler.harvest!)
    end

    def test_merge_avoids_dups
      sample = sample_with(:duration => 1)
      @sampler.merge!([sample, sample])
      assert_equal([sample], @sampler.harvest!)
    end

    def test_harvest_avoids_dups_from_harvested_samples
      sample = sample_with(:duration => 2.5)
      @sampler.store_sample(sample)
      @sampler.store_sample(sample)

      assert_equal([sample], @sampler.harvest!)
    end

    def test_harvest_adding_slowest
      sample = sample_with(:duration => 2.5)
      @sampler.store_sample(sample)

      assert_equal([sample], @sampler.harvest!)
    end

    def test_harvest_new_slower_sample_replaces_older
      faster_sample = sample_with(:duration => 5.0)
      slower_sample = sample_with(:duration => 10.0)

      @sampler.store_sample(slower_sample)
      @sampler.merge!([faster_sample])

      assert_equal([slower_sample], @sampler.harvest!)
    end

    def test_harvest_keep_older_slower_sample
      faster_sample = sample_with(:duration => 5.0)
      slower_sample = sample_with(:duration => 10.0)

      @sampler.store_sample(faster_sample)
      @sampler.merge!([slower_sample])

      assert_equal([slower_sample], @sampler.harvest!)
    end

    class BoundlessBuffer < Transaction::TransactionSampleBuffer
      def capacity
        1.0 / 0 # Can't use Float::INFINITY on older Rubies :(
      end
    end

    def test_harvest_has_hard_maximum
      boundless_buffer = BoundlessBuffer.new

      buffers = @sampler.instance_variable_get(:@sample_buffers)
      buffers << boundless_buffer

      samples = generate_samples(100)
      samples.each do |sample|
        @sampler.store_sample(sample)
      end

      result = @sampler.harvest!
      assert_equal Transaction::TransactionSampleBuffer::SINGLE_BUFFER_MAX, result.length
    end

    # Tests below this line are functional tests for the sampler, not
    # unit tests per se - some overlap with the tests above, but
    # generally usefully so

    def test_sample__gc_stats
      GC.extend MockGCStats
      # These are effectively Garbage Collects, detected each time GC.time is
      # called by the transaction sampler.  One time value in seconds for each call.
      MockGCStats.mock_values = [0,0,0,1,0,0,1,0,0,0,0,0,0,0,0]

      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do

        in_transaction 'a' do
          segment_b = Tracer.start_segment name: "b"
          segment_b.finish

          segment_c = Tracer.start_segment name: "c"
          segment_d = Tracer.start_segment name: "d"
          segment_d.finish
          segment_c.finish
        end

        sample = last_transaction_trace
        assert_equal "ROOT{a{b,c{d}}}", sample.to_s_compact
      end
    ensure
      MockGCStats.mock_values = []
    end

    # NB this test occasionally fails due to a GC during one of the
    # sample traces, for example. It's unfortunate, but we can't
    # reliably turn off GC on all versions of ruby under test
    def test_harvest_slowest
      nr_freeze_time
      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do
          s = Tracer.start_segment name: 'first'
          advance_time 0.1
          s.finish
        end
        in_transaction do
          s = Tracer.start_segment name: 'second'
          advance_time 0.1
          s.finish
        end

        in_transaction do
          s = Tracer.start_segment name: 'two_seconds'
          advance_time 2
          s.finish
        end

        in_transaction do
          s = Tracer.start_segment name: 'fourth'
          advance_time 0.1
          s.finish
        end
        in_transaction do
          s = Tracer.start_segment name: 'fifth'
          advance_time 0.1
          s.finish
        end

        slowest = @sampler.harvest![0]
        first_duration = slowest.duration
        assert((first_duration.round >= 2),
               "expected sample duration = 2, but was: #{slowest.duration.inspect}")

        # 1 second duration
        in_transaction do
          s = Tracer.start_segment name: 'one_second'
          advance_time 1
          s.finish
        end
        @sampler.merge!([slowest])
        not_as_slow = @sampler.harvest![0]
        assert((not_as_slow == slowest), "Should re-harvest the same transaction since it should be slower than the new transaction - expected #{slowest.inspect} but got #{not_as_slow.inspect}")

        # 1 second duration
        in_transaction do
          s = Tracer.start_segment name: 'ten_seconds'
          advance_time 10
          s.finish
        end

        @sampler.merge!([slowest])
        new_slowest = @sampler.harvest![0]
        assert((new_slowest != slowest), "Should not harvest the same trace since the new one should be slower")
        assert_equal(new_slowest.duration.round, 10, "Slowest duration must be = 10, but was: #{new_slowest.duration.inspect}")
      end
      nr_unfreeze_time
    end

    def test_harvest_prepare_samples
      samples = [mock('TT0'), mock('TT1')]
      samples[0].expects(:prepare_to_send!)
      samples[1].expects(:prepare_to_send!)
      @sampler.stubs(:harvest_from_sample_buffers).returns(samples)
      prepared = @sampler.harvest!
      assert_equal(samples, prepared)
    end

    def test_harvest_prepare_samples_with_error
      samples = [mock('TT0'), mock('TT1')]
      samples[0].expects(:prepare_to_send!).raises('an error')
      samples[1].expects(:prepare_to_send!)
      @sampler.stubs(:harvest_from_sample_buffers).returns(samples)
      prepared = @sampler.harvest!
      assert_equal([samples[1]], prepared)
    end

    def test_custom_params_include_gc_time
      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do
          StatsEngine::GCProfiler.stubs(:record_delta).returns(10.0)
        end
      end

      assert_equal 10.0, intrinsic_attributes_from_last_sample[:gc_time]
    end

    def test_custom_params_include_tripid

      DistributedTracing::CrossAppMonitor.any_instance.stubs(:client_referring_transaction_trip_id).returns('PDX-NRT')

      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do |transaction|
          txn_info = [transaction.guid, true, 'PDX-NRT']
          payload = CrossAppPayload.new('1#666', transaction, txn_info)
          transaction.distributed_tracer.cross_app_payload = payload
          transaction.distributed_tracer.is_cross_app_caller = true
        end
      end

      assert_equal 'PDX-NRT', intrinsic_attributes_from_last_sample[:trip_id]
    end

    def test_custom_params_dont_include_tripid_if_not_cross_app_transaction
      DistributedTracing::CrossAppMonitor.any_instance.stubs(:client_referring_transaction_trip_id).returns('PDX-NRT')

      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do |transaction|
          transaction.distributed_tracer.is_cross_app_caller = false
        end
      end

      assert_nil intrinsic_attributes_from_last_sample[:trip_id]
    end

    def test_custom_params_include_path_hash
      path_hash = nil

      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do |transaction|
          transaction.distributed_tracer.is_cross_app_caller = true
          path_hash = transaction.distributed_tracer.cat_path_hash
        end
      end

      assert_equal path_hash, intrinsic_attributes_from_last_sample[:path_hash]
    end

    def test_synthetics_parameters_not_included_if_not_valid_synthetics_request
      with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
        in_transaction do |txn|
          txn.raw_synthetics_header = nil
          txn.synthetics_payload = nil
        end
      end

      sample = NewRelic::Agent.agent.transaction_sampler.harvest!.first

      intrinsic_attributes = attributes_for(sample, :intrinsic)
      assert_nil sample.synthetics_resource_id
      assert_nil intrinsic_attributes[:synthetics_resource_id]
      assert_nil intrinsic_attributes[:synthetics_job_id]
      assert_nil intrinsic_attributes[:synthetics_monitor_id]
    end

    def test_synthetics_parameters_included
      in_transaction do |txn|
        txn.raw_synthetics_header = ""
        txn.synthetics_payload = [1, 1, 100, 200, 300]
      end

      sample = NewRelic::Agent.agent.transaction_sampler.harvest!.first

      intrinsic_attributes = attributes_for(sample, :intrinsic)
      assert_equal 100, sample.synthetics_resource_id
      assert_equal 100, intrinsic_attributes[:synthetics_resource_id]
      assert_equal 200, intrinsic_attributes[:synthetics_job_id]
      assert_equal 300, intrinsic_attributes[:synthetics_monitor_id]
    end

    class Dummy
      include Instrumentation::ControllerInstrumentation
      def run(n)
        n.times do
          perform_action_with_newrelic_trace(:name => 'smile') do
          end
        end
      end
    end

    # TODO: this test seems to be destabilizing CI in a way that I don't grok.
    #def sadly_do_not_test_harvest_during_transaction_safety
    #  n = 3000
    #  harvester = Thread.new do
    #    n.times { @sampler.harvest! }
    #  end

    #  Dummy.new.run(n)

    #  harvester.join
    #end

    private

    SAMPLE_DEFAULTS = {
      :threshold => 1.0,
      :transaction_name => nil
    }

    def sample_with(incoming_opts = {})
      opts = SAMPLE_DEFAULTS.dup
      opts.merge!(incoming_opts)

      attributes = Attributes.new(NewRelic::Agent.instance.attribute_filter)
      attributes.add_intrinsic_attribute(:synthetics_resource_id, opts[:synthetics_resource_id])

      sample = Transaction::Trace.new(Time.now)
      sample.attributes = attributes
      sample.threshold = opts[:threshold]
      sample.transaction_name = opts[:transaction_name]
      sample.stubs(:duration).returns(opts[:duration])
      sample
    end

    def generate_samples(count, opts = {})
      (1..count).map do |millis|
        sample_with(opts.merge(:duration => (millis / 1000.0)))
      end
    end

    def run_long_sample_trace(n)
      @sampler.on_start_transaction(@state, Time.now)
      n.times do |i|
        @sampler.notice_push_frame(@state)
        yield if block_given?
        @sampler.notice_pop_frame(@state, "node#{i}")
      end
      @sampler.on_finishing_transaction(@state, @txn)
    end

    def run_sample_trace(start = Time.now.to_f, stop = nil, state = @state)
      @sampler.on_start_transaction(state, start)
      @sampler.notice_push_frame(state)
      @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", {}, 0, state)
      @sampler.notice_push_frame(state)
      @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", {}, 0, state)
      yield if block_given?
      @sampler.notice_pop_frame(state, "ab")
      @sampler.notice_push_frame(state)
      @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", {}, 0, state)
      @sampler.notice_pop_frame(state, "ac")
      @sampler.notice_pop_frame(state, "a")
      @sampler.on_finishing_transaction(state, @txn)
    end

    def intrinsic_attributes_from_last_sample
      sample = NewRelic::Agent.agent.transaction_sampler.harvest!.first
      attributes_for(sample, :intrinsic)
    end
  end
end