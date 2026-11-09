require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "the last owner can't be demoted or removed" do
    owner = memberships(:amina_acme)

    assert_not owner.update(role: :manager)
    assert_not owner.reload.destroy
    assert owner.reload.owner?
  end

  test "an owner can be demoted once there is another owner" do
    memberships(:carl_acme).update!(role: :owner)

    assert memberships(:amina_acme).update(role: :manager)
  end

  test "adding a new person creates their user" do
    membership = accounts(:acme).memberships.create!(user_attributes: { name: "Njeri", email_address: " NJERI@acme.test " }, role: :stock_clerk)

    assert_equal "njeri@acme.test", membership.user.email_address
    assert membership.stock_clerk?
  end

  test "adding someone who already uses HardPoint links their existing user" do
    assert_no_difference -> { User.count } do
      accounts(:acme).memberships.create!(user_attributes: { name: "ignored", email_address: users(:bob).email_address })
    end
  end

  test "a person can only be added once" do
    duplicate = accounts(:acme).memberships.new(user: users(:carl))

    assert_not duplicate.save
    assert_includes duplicate.errors[:user], "is already a member of this shop"
  end

  test "staff can be bound to one branch; owners never are" do
    carl = memberships(:carl_acme)
    assert_not carl.bound_to_branch?
    assert_equal accounts(:acme).branches.count, carl.visible_branches.count

    carl.update!(branch: branches(:acme_yard))
    assert_equal [ branches(:acme_yard) ], carl.visible_branches.to_a
    assert carl.sees_branch?(branches(:acme_yard))
    assert_not carl.sees_branch?(branches(:acme_main))

    carl.branch = branches(:bolt_main)
    assert_not carl.valid?
    assert_match "one of this shop's", carl.errors.full_messages.to_sentence

    amina = memberships(:amina_acme)
    amina.branch = branches(:acme_yard)
    assert_not amina.valid?
    assert_match "owners see every branch", amina.errors.full_messages.to_sentence
  end

  test "permissions follow the role" do
    assert memberships(:amina_acme).can_manage_staff?
    assert_not memberships(:carl_acme).can_manage_staff?
    assert_not memberships(:carl_acme).can_manage_branches?
  end
end
