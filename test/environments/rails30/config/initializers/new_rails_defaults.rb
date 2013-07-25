# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(ActiveRecord)
  ActiveRecord::Base.include_root_in_json = true
  ActiveRecord::Base.store_full_sti_class = true
end

ActiveSupport.use_standard_json_time_format = true
ActiveSupport.escape_html_entities_in_json = false
