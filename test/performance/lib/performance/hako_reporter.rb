# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class HakoReporter
    def initialize(results, elapsed, options = {})
      @results = results
      @token = ENV['HAKO_TOKEN'] || options[:hako_token]
    end

    def report
      Performance.logger.info("Uploading #{@results.size} results to Hako")
      client = HakoClient.new(@token)
      @results.each do |result|
        rsp = client.submit(result)
        case rsp
        when Net::HTTPSuccess
          Performance.logger.debug("Successfully posted result to Hako")
        else
          Performance.logger.error("Failed to post results to Hako: #{rsp.inspect}")
        end
      end
    end
  end
end
