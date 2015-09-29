# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ErrorCollectorTests < Performance::TestCase
  def setup
    @txn_name = "Controller/blogs/index".freeze
    @err_msg = "Sorry!".freeze
  end

  def test_notice_error
    measure do
      in_transaction :name => @txn_name do
        NewRelic::Agent.notice_error StandardError.new @err_msg
      end
    end
  end

  def test_notice_error_with_custom_attributes
    opts = {:custom_params => {:name => "Wes Mantooth", :channel => 9}}

    measure do
      in_transaction :name => @txn_name do
        NewRelic::Agent.notice_error StandardError.new(@err_msg), opts
      end
    end
  end
end
