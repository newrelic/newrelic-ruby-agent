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
      if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('4.0.0')
        version 'v4', :using => :accept_version_header
      end

      format :json

      resource :fish do
        get do
          "api v4"
        end
      end
    end

    class Unversioned < Grape::API
      format :json

      resource :fish do
        get do
          "api v5"
        end
      end
    end
  end
end