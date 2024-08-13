# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

require_relative '../../test_helper'

module NewRelic::Agent
  class ServerlessHandlerEventSourcesTest < Minitest::Test
    def test_hash_sanity
      hash = ServerlessHandlerEventSources.to_hash
      resources = %w[alb apiGateway apiGatewayV2 cloudFront cloudWatchScheduled dynamoStreams firehose kinesis s3 ses
        sns sqs]

      assert_equal(resources.sort, hash.keys.sort)
      assert_equal(%w[records #size], hash['firehose']['attributes']['aws.lambda.eventSource.length'])
      assert_equal(['Records', 0, 's3', 'object', 'size'],
        hash['s3']['attributes']['aws.lambda.eventSource.objectSize'])
    end

    def test_transform_dig_functionality
      input = 'action.collection[1138].key'

      assert_equal(['action', 'collection', 1138, 'key'], ServerlessHandlerEventSources.transform(input))
    end

    def test_transform_length_functionality
      input = 'a.collection.length'

      assert_equal(['a', 'collection', '#size'], ServerlessHandlerEventSources.transform(input))
    end

    def test_transform_pass_through_functionality
      input = 'simple'

      assert_equal([input], ServerlessHandlerEventSources.transform(input))
    end
  end
end
