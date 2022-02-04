# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

BLOCK_PATH = '/usr/local/antonius-block'

def docker?
  File.exist?('/.dockerenv')
end

def bundler_environment_variables
  return unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')

  variables = [bundler_build_mysql2, bundler_build_curb].compact
  variables.join(' ') + ' ' if variables
end

# Ruby <= 2.4.0 requires OpenSSL v1.0 and MySQL v5.5 (which uses OpenSSL v1.0)
# Source these from the home directory if available
def bundler_build_mysql2
  return unless Dir.exist?(docker_openssl_dir) && Dir.exist?(docker_mysql_dir)

  "BUNDLE_BUILD__MYSQL2='--with-mysql-dir=#{docker_mysql_dir} " + \
                        "--with-mysql-config=#{docker_mysql_dir}/bin/mysql_config " + \
                        "--with-mysql-rpath=#{docker_mysql_dir}/bin --with-openssl-dir=#{docker_openssl_dir}'"
end

def bundler_build_curb
  return unless Dir.exist?(docker_curl_dir)

  "BUNDLE_BUILD__CURB='--with-curl-dir=#{docker_curl_dir}'"
end

def docker_curl_dir
  File.join(BLOCK_PATH, 'curl7_openssl1.0')
end

def docker_mysql_dir
  File.join(BLOCK_PATH, 'mysql5.5')
end

def docker_openssl_dir
  File.join(BLOCK_PATH, 'openssl1.0')
end
