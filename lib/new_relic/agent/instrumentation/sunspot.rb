if defined?(Sunspot)
  module Sunspot
    class << self
    %w(index index! commit search more_like_this remove remove! remove_by_id remove_by_id! remove_all remove_all! batch).each do |method|
        add_method_tracer method, "Solr/Sunspot/#{method}"
      end
    end
  end
end
