# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/instrumentation/action_mailer_subscriber'

module NewRelic::Agent::Instrumentation
  class TestMailer < ActionMailer::Base
    default to: 'karras@mechanists.com',
      from: 'garret@thecity.org',
      reply_to: 'viktoria@constantine.net'

    def test_action; end

    def welcome
      headers['X-SPAM'] = 'Not SPAM'
      mail({subject: "Findings from Truart's estate",
            body: '<html><body>Regarding the mechanical servants...</body></html>'})
    end
  end

  class ActionMailerSubscriberTest < Minitest::Test
    ACTION = 'deliver'
    NAME = "#{ACTION}.action_mailer"
    ID = 1947
    SUBSCRIBER = NewRelic::Agent::Instrumentation::ActionMailerSubscriber.new
    MAILER = TestMailer.new

    def setup
      @delivery_method = ActionMailer::Base.delivery_method
      ActionMailer::Base.delivery_method = :test
    end

    def teardown
      ActionMailer::Base.delivery_method = @delivery_method
    end

    def test_start
      in_transaction do |txn|
        time = Time.now.to_f
        SUBSCRIBER.start(NAME, ID, {mailer: MAILER.class.name})
        segment = txn.segments.last

        assert_in_delta time, segment.start_time
        assert_equal "Ruby/ActionMailer/#{MAILER.class.name}/#{ACTION}", segment.name
      end
    end

    def test_start_when_not_traced
      SUBSCRIBER.state.stub :is_execution_traced?, false do
        in_transaction do |txn|
          SUBSCRIBER.start(NAME, ID, {})

          assert_empty txn.segments
        end
      end
    end

    def test_start_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, ArgumentError]

        in_transaction do |txn|
          SUBSCRIBER.stub :start_segment, -> { raise 'kaboom' } do
            SUBSCRIBER.start(NAME, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    def test_finish
      in_transaction do |txn|
        started_segment = NewRelic::Agent::Tracer.start_transaction_or_segment(name: NAME, category: :testing)
        SUBSCRIBER.push_segment(ID, started_segment)

        time = Time.now.to_f
        SUBSCRIBER.finish(NAME, ID, {})
        segment = txn.segments.last

        assert_in_delta time, segment.end_time
        assert_predicate(segment, :finished?)
      end
    end

    def test_finish_with_exception_payload
      skip_unless_minitest5_or_above

      exception_object = StandardError.new
      noticed = false
      segment = MiniTest::Mock.new
      segment.expect :notice_error, nil, [exception_object]
      SUBSCRIBER.stub(:pop_segment, segment, [ID]) do
        SUBSCRIBER.finish(NAME, ID, {exception_object: exception_object})
      end

      segment.verify
    end

    def test_finish_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, RuntimeError]

        in_transaction do |txn|
          SUBSCRIBER.state.stub :is_execution_traced?, -> { raise 'kaboom' } do
            SUBSCRIBER.finish(NAME, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    def test_an_actual_mailer_process_call
      in_transaction do |txn|
        MAILER.process(:test_action)

        assert_equal 2, txn.segments.size
        assert_equal "Ruby/ActionMailer/#{TestMailer.name}/process", txn.segments.last.name
        assert_equal :test_action, txn.segments.last.params[:action]
      end
    end

    # TODO: test flakes on mail() processing attachments when there aren't any
    # def test_an_actual_mail_delivery
    #   in_transaction do |txn|
    #     MAILER.welcome.deliver

    #     assert_equal 2, txn.segments.size
    #     assert_match %r{^Ruby/ActionMailer/.*/deliver$}, txn.segments.last.name
    #     # assert_equal "Ruby/ActionMailer/#{TestMailer.name}/deliver", txn.segments.last.name
    #   end
    # end
  end
end
