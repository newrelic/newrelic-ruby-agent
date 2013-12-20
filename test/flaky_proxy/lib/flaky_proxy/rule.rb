# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module FlakyProxy
  class Rule
    class ActionBuilder
      def initialize(rule)
        @actions = []
        @rule = rule
      end

      def pass
        @rule.actions << [:pass]
      end

      def respond(response_spec)
        @rule.actions << [:respond, response_spec]
      end

      def delay(amount)
        @rule.actions << [:delay, amount]
      end

      def close
        @rule.actions << [:close]
      end
    end

    attr_reader :actions

    def initialize(url_regex=nil, &blk)
      @url_regex = url_regex
      @action = blk
      @actions = []
      @builder = ActionBuilder.new(self)
      @default_action = [:pass]
    end

    def match?(request)
      @url_regex.nil? || @url_regex.match(request.request_url)
    end

    def next_action
      @actions.shift || @default_action
    end

    def relay(request, connection)
      request.relay_to(connection.server_socket)
      response = Response.read_from(connection.server_socket)
      response.relay_to(connection.client_socket)
    end

    def evaluate(request, connection)
      @builder.instance_exec(request, connection, &@action)
      action, *params = next_action
      FlakyProxy.logger.info("    [#{action.upcase}] #{request.request_method} #{request.request_url}")
      case action
      when :pass
        relay(request, connection)
      when :respond
        response_spec = params.first
        response = Response.build(response_spec)
        response.relay_to(connection.client_socket)
      when :delay
        amount = params.first
        sleep(amount)
        relay(request, connection)
      when :close
        connection.client_socket.close
      end
    end
  end
end
