# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module MetricParser
    module JavaParser
      def class_name_without_package
        full_class_name =~ /(.*\.)(.*)$/ ? $2 : full_class_name
      end

      def developer_name
        "#{full_class_name}.#{method_name}()"
      end

      def short_name
        "#{class_name_without_package}.#{method_name}()"
      end
    end
  end
end
