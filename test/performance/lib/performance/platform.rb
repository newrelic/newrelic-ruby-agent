# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Platform
    def self.current
      @current ||= self.new
    end

    def jruby?
      defined?(JRUBY_VERSION)
    end

    def ree?
      defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /MBARI/
    end

    def match?(p)
      case p
      when :jruby   then jruby?
      when :mri     then !jruby?
      when :ree     then !jruby? && ree?
      when :mri_18  then !jruby? && RUBY_VERSION =~ /^1\.8\./
      when :mri_19  then !jruby? && RUBY_VERSION =~ /^1\.9\./
      when :mri_193 then !jruby? && RUBY_VERSION =~ /^1\.9\.3/
      when :mri_20  then !jruby? && RUBY_VERSION =~ /^2\.0\./
      when :mri_21  then !jruby? && RUBY_VERSION =~ /^2\.1\./
      when :mri_22  then !jruby? && RUBY_VERSION =~ /^2\.2\./
      end
    end

    def match_any?(platforms)
      platforms.any? { |p| match?(p) }
    end
  end
end
