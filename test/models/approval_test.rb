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

  test "guessing is cut off at that till: after too many wrong PINs even the right one waits there" do
    front, back = @account.sessions.create!(user: users(:carl)), @account.sessions.create!(user: users(:carl))
    Approval::FAILURES_ALLOWED.times { |i| assert_nil Approval.approver_for(@account, format("%04d", 9000 + i), session: front) }

    assert_nil Approval.approver_for(@account, "2468", session: front)
    assert Approval.locked?(@account, front)
    assert_not Approval.locked?(@account, back), "another till carries on"
    assert_equal users(:amina), Approval.approver_for(@account, "2468", session: back)
    assert_not Approval.locked?(accounts(:bolt)), "other shops aren't affected"

    travel Approval::WINDOW + 1.minute do
      assert_equal users(:amina), Approval.approver_for(@account, "2468", session: front)
    end
  end

  test "guessing spread over many sign-ins is still cut off for the shop" do
    Approval::SHOP_FAILURES_ALLOWED.times { |i| Approval.approver_for(@account, format("%04d", 9000 + i), session: @account.sessions.create!(user: users(:carl))) }
    assert_nil Approval.approver_for(@account, "2468", session: @account.sessions.create!(user: users(:carl)))
  end

  test "two approvers can't share an approval PIN" do
    sara = memberships(:sara_acme)
    sara.update!(role: "manager")
    assert_not sara.set_approval_pin("2468")
    assert_match "already used", sara.errors.full_messages.to_sentence
    assert sara.set_approval_pin("1357")

    assert memberships(:amina_acme).set_approval_pin("2468"), "keeping your own PIN is fine"
  end
end
