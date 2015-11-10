# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/request_attributes'

module NewRelic
  module Agent
    class Transaction
      class RequestAttributesTest < Minitest::Test

        def test_tolerates_request_without_desired_methods
          request = stub 'request'
          attrs = RequestAttributes.new request

          assert_equal "/", attrs.request_path
          assert_nil attrs.referer
          assert_nil attrs.content_length
          assert_nil attrs.content_type
          assert_nil attrs.host
          assert_nil attrs.user_agent
          assert_nil attrs.request_method
        end

        def test_sets_referer_from_request
          request = stub 'request', :referer => "http://site.com/page"
          attrs = RequestAttributes.new request

          assert_equal "http://site.com/page", attrs.referer
        end

        def test_sets_accept_from_request_headers
          request = stub 'request', :env => {"HTTP_ACCEPT" => "application/json"}
          attrs = RequestAttributes.new request

          assert_equal "application/json", attrs.accept
        end

        def test_sets_content_length_from_request
          request = stub 'request', :content_length => "111"
          attrs = RequestAttributes.new request

          assert_equal 111, attrs.content_length
        end

        def test_sets_content_type_from_request
          request = stub 'request', :content_type => "application/json"
          attrs = RequestAttributes.new request

          assert_equal "application/json", attrs.content_type
        end

        def test_sets_host_from_request
          request = stub 'request', :host => "localhost"
          attrs = RequestAttributes.new request

          assert_equal "localhost", attrs.host
        end

        def test_sets_port_from_request
          request = stub 'request', :port => "3000"
          attrs = RequestAttributes.new request

          assert_equal 3000, attrs.port
        end

        def test_sets_user_agent_from_request
          request = stub 'request', :user_agent => "use this!"
          attrs = RequestAttributes.new request

          assert_equal "use this!", attrs.user_agent
        end

        def test_sets_method_from_request
          request = stub 'request', :request_method => "POST"
          attrs = RequestAttributes.new request

          assert_equal "POST", attrs.request_method
        end
      end
    end
  end
end
