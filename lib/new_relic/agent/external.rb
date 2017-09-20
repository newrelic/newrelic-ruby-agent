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
    end
  end
end