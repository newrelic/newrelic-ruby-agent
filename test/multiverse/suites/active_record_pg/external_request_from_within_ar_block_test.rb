# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net/http'

class ExternalRequestFromWithinARBlockTest < Minitest::Test
  # Use the agent's segment callback system to register a callback for the
  # ExternalRequestSegment class. Every time that class is initialized, the
  # callback will be called and it will check to see if the external request
  # segment has been created from within an ActiveRecord transaction block.
  # If that check succeeds, generate an error and have the agent notice it.
  def test_callback_to_notice_error_if_an_external_request_is_made_within_an_ar_block
    callback = proc do
      return unless caller.any? { |line| line.match?(%r{active_record/transactions.rb}) }

      caller = respond_to?(:name) ? name : '(unknown)'
      klass = respond_to?(:class) ? self.class.name : '(unknown)'
      method = __method__ || '(unknown)'

      msg = 'External request made from within an ActiveRecord transaction:' +
        "\ncaller=#{caller}\nclass=#{klass}\nmethod=#{method}"
      error = StandardError.new(msg)
      NewRelic::Agent.notice_error(error)
    end

    NewRelic::Agent::Transaction::ExternalRequestSegment.set_segment_callback(callback)

    in_transaction do |txn|
      ActiveRecord::Base.transaction do
        perform_net_request
      end

      # in_transaction creates a dummy segment on its own, and we expect another
      assert_equal 2, txn.segments.size
      segment = txn.segments.detect { |s| s.name.start_with?('External/') }

      assert segment, "Failed to find an 'External/' request segment"
      error = segment.noticed_error

      assert error, "The 'External/' request segment did not contain a noticed error"
      assert_match 'External request made from within an ActiveRecord transaction', error.message
    end
  end

  private

  def perform_net_request
    uri = URI('https://newrelic.com')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.get('/')
  end
end
