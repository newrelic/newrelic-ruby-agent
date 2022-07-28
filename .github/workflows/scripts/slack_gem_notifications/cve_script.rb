# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This script runs on a 24 hour cycle via gem_notifications.yml and sends slack updates for Ruby CVEs.

require_relative 'cve_methods'

check_for_cves
