module NewRelic
  module Agent
    module Configuration
      class EnvironmentSource < ::Hash
        def initialize
          string_map = {
            'NRCONFIG'              => 'config_path',
            'NEW_RELIC_LICENSE_KEY' => 'license_key',
            'NEWRELIC_LICENSE_KEY'  => 'license_key',
            'NEW_RELIC_APP_NAME'    => 'app_name',
            'NEWRELIC_APP_NAME'     => 'app_name',
            'NEW_RELIC_LOG'         => 'log_file_path',
            'NEW_RELIC_DISPATCHER'  => 'dispatcher',
            'NEWRELIC_DISPATCHER'   => 'dispatcher',
            'NEW_RELIC_FRAMEWORK'   => 'framework',
            'NEWRELIC_FRAMEWORK'    => 'framework'
          }.each do |key, val|
            self[val] = ENV[key] if ENV[key]
          end

          boolean_map = {
            'NEWRELIC_ENABLE' => 'enabled'
          }.each do |key, val|
            if ENV[key].to_s =~ /false|off|no/i
              self[val] = false
            elsif ENV[key] != nil
              self[val] = true
            end
          end

          self.freeze
        end
      end
    end
  end
end
