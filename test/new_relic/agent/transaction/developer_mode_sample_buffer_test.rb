# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Transaction
  class DeveloperModeSampleBufferTest < Minitest::Test
    def setup
      @buffer = DeveloperModeSampleBuffer.new
    end

    def test_store_sample_for_developer_mode_in_dev_mode
      with_config(:developer_mode => true) do
        sample = stub
        @buffer.store(sample)
        assert_equal([sample], @buffer.samples)
      end
    end

    def test_store_sample_for_developer_mode_not_in_dev_mode
      with_config(:developer_mode => false) do
        @buffer.store(stub)
        assert(@buffer.samples.empty?)
      end
    end

    def test_stores_up_to_truncate_max
      with_config(:developer_mode => true) do
        sample = stub
        @buffer.capacity.times { @buffer.store(sample) }

        assert_equal(Array.new(@buffer.capacity, sample), @buffer.samples)
      end
    end

    def test_stores_and_truncates
      with_config(:developer_mode => true) do
        sample = stub
        (@buffer.capacity * 2).times { @buffer.store(sample) }

        assert_equal(Array.new(@buffer.capacity, sample), @buffer.samples)
      end
    end

    def test_visit_node_takes_backtraces_in_dev_mode
      with_config(:developer_mode => true) do
        node = {}
        @buffer.visit_node(node)
        assert node[:backtrace].any? {|trace_line| trace_line.include?(__FILE__)}
      end
    end

    def test_visit_node_takes_backtraces_not_in_dev_mode
      with_config(:developer_mode => false) do
        node = {}
        @buffer.visit_node(node)
        assert_nil node[:backtrace]
      end
    end

    def test_visit_node_safe_against_nils
      with_config(:developer_mode => true) do
        @buffer.visit_node(nil)
      end
    end

    def test_doesnt_store_previous
      with_config(:developer_mode => true) do
        @buffer.store_previous([stub])
        assert @buffer.samples.empty?
      end
    end
  end
end
