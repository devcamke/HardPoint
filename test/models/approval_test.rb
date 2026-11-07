require "test_helper"

class ApprovalTest < ActiveSupport::TestCase
  setup do
    Approval.cache = ActiveSupport::Cache::MemoryStore.new
    @account = accounts(:acme)
    Current.account = @account
    memberships(:amina_acme).update!(approval_pin: "2468")
  end

  teardown { Approval.cache = nil }

  test "the right approval PIN names the approver; a wrong one names nobody" do
    assert_equal users(:amina), Approval.approver_for(@account, "2468")
    assert_nil Approval.approver_for(@account, "1111")
    assert_nil Approval.approver_for(@account, "")
  end

  test "guessing is cut off: after too many wrong PINs even the right one waits" do
    Approval::FAILURES_ALLOWED.times { |i| assert_nil Approval.approver_for(@account, format("%04d", 9000 + i)) }

    assert_nil Approval.approver_for(@account, "2468")
    assert Approval.locked?(@account)
    assert_not Approval.locked?(accounts(:bolt)), "other shops aren't affected"

    travel Approval::WINDOW + 1.minute do
      assert_equal users(:amina), Approval.approver_for(@account, "2468")
    end
  end
end
