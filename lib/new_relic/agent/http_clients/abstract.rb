# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module HTTPClients

      # This class provides a public interface for wrapping HTTP requests. This
      # may be used to create wrappers that are compatible with New Relic's
      # external request API.
      #
      # @api public
      class AbstractRequest
        ERROR_MESSAGE = 'Subclasses of NewRelic::Agent::HTTPClients::AbstractRequest must implement a'

        def []
          raise NotImplementedError, "#{ERROR_MESSAGE} :[] method"
        end

        def []=
          raise NotImplementedError, "#{ERROR_MESSAGE} :[]= method"
        end

        def host_from_header
          raise NotImplementedError, "#{ERROR_MESSAGE} :host_from_header method"
        end
      end

      # This class provides a public interface for wrapping HTTP responses. This
      # is used internally adaptor patterns onto various HTTP client response objects.
      #
      # @api private
      class AbstractResponse # :nodoc:
        ERROR_MESSAGE = 'Subclasses of NewRelic::Agent::HTTPClients::AbstractResponse must implement a'

        def initialize response
          @response = response
        end

        def status_code
          raise NotImplementedError, "#{ERROR_MESSAGE} :status_code method"
        end
      end
    end
  end
end
