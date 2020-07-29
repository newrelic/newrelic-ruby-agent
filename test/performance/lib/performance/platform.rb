# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module Performance
  class Platform
    def self.current
      @current ||= self.new
    end

    def jruby?
      defined?(JRUBY_VERSION)
    end

    def match?(p)
      case p
      when :jruby   then jruby?
      when :mri     then !jruby?
      when :mri_20  then !jruby? && RUBY_VERSION =~ /^2\.0\./
      when :mri_21  then !jruby? && RUBY_VERSION =~ /^2\.1\./
      when :mri_22  then !jruby? && RUBY_VERSION =~ /^2\.2\./
      when :mri_23  then !jruby? && RUBY_VERSION =~ /^2\.3\./
      when :mri_24  then !jruby? && RUBY_VERSION =~ /^2\.4\./
      when :mri_25  then !jruby? && RUBY_VERSION =~ /^2\.5\./
      when :mri_26  then !jruby? && RUBY_VERSION =~ /^2\.6\./
      end
    end

    def match_any?(platforms)
      platforms.any? { |p| match?(p) }
    end
  end
end
