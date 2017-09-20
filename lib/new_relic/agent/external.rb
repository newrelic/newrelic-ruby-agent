# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/external_request_segment'

module NewRelic
  module Agent
    module External

      # This method creates and starts an external request segment using the
      # given library, URI, and procedure. This is used to time external calls
      # made over HTTP.
      #
      # +library+ should be a string of the class name of the library used to
      # make the external call, for example, 'Net::HTTP'.
      #
      # +uri+ should be a URI object or a string indicating the URI to which the
      # external request is being made. The URI should begin with the protocol, 
      # for example, 'https://github.com'.
      #
      # +procedure+ should be the HTTP method being used for the external
      # request as a string, for example, 'GET'.
      #
      # @api public
      def self.start_external_segment(library: nil, uri: nil, procedure: nil)
        raise ArgumentError, 'Argument `library` is required' if library.nil?
        raise ArgumentError, 'Argument `uri` is required' if uri.nil?
        raise ArgumentError, 'Argument `procedure` is required' if procedure.nil?

        ::NewRelic::Agent::Transaction::Tracing.start_external_request_segment(
                                                                                library,
                                                                                uri,
                                                                                procedure
                                                                              )
      end

      # This method adds New Relic request headers to a given request made to an 
      # external API and checks to see if a host header is used for the request.
      # If a host header is used, it updates the segment name to match the host
      # header.
      #
      # +request+ should be a NewRelic::Agent::HTTPClients::NetHTTPRequest object
      #
      # @api public
      def self.add_request_headers(request: nil)
        raise ArgumentError, 'Argument `request` is required' if request.nil?

        @segment.add_request_headers(request) if @segment
      end

      # This method extracts app data from an external response if present. If
      # a valid cross-app ID is found, the name of the segment is updated to
      # reflect the cross-process ID and transaction name.
      #
      # +response+ should be a hash of headers.
      #
      # @api public
      def self.read_response_headers(response: nil)
        raise ArgumentError, 'Argument `response` is required' if response.nil?

        @segment.read_response_headers(response) if @segment
      end
    end
  end
end