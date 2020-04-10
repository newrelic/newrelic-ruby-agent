# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'test_helper'

class FakeTraceObserver < Com::Newrelic::Trace::V1::IngestService::Service
  def initialize
    @seen = 0
    @next_seen_hurdle = 10
    @record_spans = nil
  end

  def record_span(record_spans, _call)
    @record_spans = record_spans
    handle
  end

  def record_status
    puts "RECORDS SEEN: #{@seen}" unless quiet?
    Com::Newrelic::Trace::V1::RecordStatus.new(messages_seen: @seen)
  end

  def handle
    return enum_for(:handle) unless block_given?
    @record_spans.each do |record_span|
      puts record_span.inspect if verbose?
      @seen += 1
      if @seen >= @next_seen_hurdle
        @next_seen_hurdle += 10
        yield record_status
      end
    end
    yield record_status
  end
end

class Server
  def initialize(port)
    @server = GRPC::RpcServer.new(pool_size: 1024, max_waiting_requests: 1024)
    @port = @server.add_http2_port("0.0.0.0:" + port.to_s, :this_port_is_insecure)
    @server.handle(FakeTraceObserver.new)
  end

  def run
    t = Thread.new {
      @server.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT'])
    }
    t.abort_on_exception
    t.join
  end

  def get_port
    @port
  end

  def stop
    @server.stop
  end
end

