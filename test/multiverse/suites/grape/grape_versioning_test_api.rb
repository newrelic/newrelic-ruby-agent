# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

unless ::Grape::VERSION == '0.1.5'
  module GrapeVersioning
    class ApiV1 < Grape::API
      version 'v1'

      format :json

      get do
        "root"
      end

      resource :fish do
        get do
          "api v1"
        end
      end
    end

    class ApiV2 < Grape::API
      version 'v2', :using => :param

      format :json

      resource :fish do
        get do
          "api v2"
        end
      end
    end

    class ApiV3 < Grape::API
      version 'v3', :using => :header, :vendor => "newrelic"

      format :json

      resource :fish do
        get do
          "api v3"
        end
      end
    end

    class ApiV4 < Grape::API
      #version from http accept header is not supported in older versions of grape
      if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('0.16.0')
        version ['v4', 'v5'], :using => :accept_version_header
      end

      format :json

      resource :fish do
        get do
          "api v4"
        end
      end
    end

    class CascadingAPI < Grape::API
      #version from http accept header is not supported in older versions of grape
      if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('0.16.0')
        version 'v5', :using => :accept_version_header
      end

      format :json

      resource :fish do
        get do
          "api v5"
        end
      end

      mount ApiV4
    end

    class Unversioned < Grape::API
      format :json

      resource :fish do
        get do
          "api v5"
        end
      end
    end

    class SharedApi < Grape::API
      format :json
      version 'v1', 'v2', 'v3', 'v4'
      resource :fish do
        get do
          "api v1-4"
        end
      end
    end

    class SharedBlockApi < Grape::API
      format :json
      version 'v1', 'v2', 'v3', 'v4' do
        resource :fish do
          get do
            "api v1-4"
          end
        end
      end
    end

    class DefaultHeaderApi < Grape::API
      format :json
      version 'v2', 'v3', :using => :header, :vendor => "newrelic"
      resource :fish do
        get do
          "api v1-4"
        end
      end
    end

    class DefaultAcceptVersionHeaderApi < Grape::API
      format :json
      version 'v2', 'v3', :using => :accept_version_header
      resource :fish do
        get do
          "api v1-4"
        end
      end
    end
  end
end
