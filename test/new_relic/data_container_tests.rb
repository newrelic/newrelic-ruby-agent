# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# To use this module to test your new data container, implement the following
# methods before including it:
#
# create_container -> create an instance of your data container class
# populate_container(container, n) -> populate the container with n items

module NewRelic
  module DataContainerTests
    def test_harvest_should_return_all_data_items
      c = create_container
      populate_container(c, 5)
      results = c.harvest!
      assert_equal(5, results.size)
    end

    def test_calling_harvest_again_should_not_return_items_again
      c = create_container
      populate_container(c, 5)

      c.harvest! # clears container
      results = c.harvest!
      assert_equal(0, results.size)
    end

    def test_calling_harvest_after_re_populating_works
      c = create_container
      populate_container(c, 5)
      assert_equal(5, c.harvest!.size)

      populate_container(c, 3)
      assert_equal(3, c.harvest!.size)
    end

    def test_reset_should_clear_stored_items
      c = create_container
      populate_container(c, 5)
      c.reset!
      assert_equal(0, c.harvest!.size)
    end

    def test_merge_should_re_integrate_items
      c = create_container
      populate_container(c, 5)
      c.merge!(c.harvest!)
      results = c.harvest!
      assert_equal(5, results.size)
    end
  end
end
