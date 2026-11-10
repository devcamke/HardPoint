require "test_helper"

class MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina), account: accounts(:acme) }

  test "index only lists this shop's staff" do
    get memberships_path

    assert_response :success
    assert_select "td", text: users(:carl).name
    assert_select "td", text: users(:bob).name, count: 0
  end

  test "adding a staff member emails them an invitation to the shop" do
    assert_difference -> { User.count } do
      perform_enqueued_jobs do
        post memberships_path, params: { membership: { role: "stock_clerk", user_attributes: { name: "Njeri", email_address: "njeri@acme.test" } } }
      end
    end

    assert_redirected_to memberships_path

    invitation = ActionMailer::Base.deliveries.last
    assert_equal [ "njeri@acme.test" ], invitation.to
    assert_match "Acme Hardware", invitation.subject
    assert_match %r{http://acme\.localhost/passwords/.+/edit}, invitation.text_part.body.to_s
  end

  test "someone who already uses HardPoint is told they've been added, not asked to choose a password" do
    assert_no_difference -> { User.count } do
      perform_enqueued_jobs do
        post memberships_path, params: { membership: { role: "cashier", user_attributes: { name: "Bob", email_address: users(:bob).email_address } } }
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ users(:bob).email_address ], mail.to
    assert_match "Acme Hardware", mail.subject
    assert_no_match "passwords/", mail.text_part.body.to_s
    assert_no_match "Choose your password", mail.html_part.body.to_s
    assert_match "http://acme.localhost/session/new", mail.text_part.body.to_s
    assert_match "your existing password", mail.text_part.body.to_s
  end

  test "adding with invalid details" do
    post memberships_path, params: { membership: { role: "cashier", user_attributes: { name: "", email_address: "not-an-email" } } }

    assert_response :unprocessable_entity
  end

  test "changing a role" do
    patch membership_path(memberships(:carl_acme)), params: { membership: { role: "manager" } }

    assert_redirected_to memberships_path
    assert Account.without_isolation { memberships(:carl_acme).reload.manager? }
  end

  test "the last owner can't be removed" do
    delete membership_path(memberships(:amina_acme))

    assert_redirected_to memberships_path
    assert Account.without_isolation { Membership.exists?(memberships(:amina_acme).id) }
  end

  test "another shop's staff can't be reached" do
    get edit_membership_path(memberships(:bob_bolt))
    assert_response :not_found

    delete membership_path(memberships(:bob_bolt))
    assert_response :not_found
  end

  test "cashiers can't manage staff" do
    sign_in_as users(:carl), account: accounts(:acme)

    get memberships_path
    assert_response :forbidden

    post memberships_path, params: { membership: { role: "owner", user_attributes: { name: "Carl's friend", email_address: "friend@x.test" } } }
    assert_response :forbidden
  end

  test "a manager manages staff but can't make, change or remove an owner" do
    Account.without_isolation { memberships(:carl_acme).update!(role: "manager") }
    sign_in_as users(:carl), account: accounts(:acme)

    patch membership_path(memberships(:carl_acme)), params: { membership: { role: "owner" } }
    assert_redirected_to memberships_path
    assert Account.without_isolation { memberships(:carl_acme).reload.manager? }, "can't promote themselves"

    assert_no_difference -> { Account.without_isolation { Membership.where(role: "owner").count } } do
      post memberships_path, params: { membership: { role: "owner", user_attributes: { name: "Friend", email_address: "friend@x.test" } } }
    end

    patch membership_path(memberships(:amina_acme)), params: { membership: { role: "cashier" } }
    delete membership_path(memberships(:amina_acme))
    assert Account.without_isolation { memberships(:amina_acme).reload.owner? }, "the owner is untouched"

    get new_membership_path
    assert_select "select[name='membership[role]'] option[value=owner]", count: 0

    patch membership_path(memberships(:sara_acme)), params: { membership: { role: "cashier" } }
    assert Account.without_isolation { memberships(:sara_acme).reload.cashier? }, "other roles are still the manager's to change"
  end

  test "removing someone signs them out everywhere, support signed in as them too" do
    session = Account.without_isolation { Session.create!(account: accounts(:acme), user: users(:carl)) }
    support = Account.without_isolation { Session.create!(account: accounts(:acme), user: users(:carl), impersonator: users(:ada), sign_in_method: "impersonation") }

    delete membership_path(memberships(:carl_acme))

    assert_not Account.without_isolation { Session.exists?(session.id) }
    assert_not Account.without_isolation { Session.exists?(support.id) }
  end

  test "a manager can't change their own role or branch" do
    Account.without_isolation { memberships(:carl_acme).update!(role: "manager", branch: branches(:acme_main)) }
    sign_in_as users(:carl), account: accounts(:acme)

    patch membership_path(memberships(:carl_acme)), params: { membership: { role: "manager", branch_id: "" } }

    assert_redirected_to memberships_path
    assert_equal branches(:acme_main), Account.without_isolation { memberships(:carl_acme).reload.branch }
  end

  test "a manager bound to a branch manages only that branch's staff, and adds people to it" do
    Account.without_isolation do
      memberships(:carl_acme).update!(role: "manager", branch: branches(:acme_main))
      memberships(:sara_acme).update!(branch: branches(:acme_yard))
    end
    sign_in_as users(:carl), account: accounts(:acme)

    get memberships_path
    assert_select "td", text: users(:sara).name, count: 0

    patch membership_path(memberships(:sara_acme)), params: { membership: { role: "cashier", branch_id: branches(:acme_main).id } }
    assert_response :not_found
    assert Account.without_isolation { memberships(:sara_acme).reload.stock_clerk? }

    post memberships_path, params: { membership: { role: "cashier", branch_id: "", user_attributes: { name: "Njeri", email_address: "njeri@acme.test" } } }
    assert_equal branches(:acme_main), Account.without_isolation { User.find_by!(email_address: "njeri@acme.test").memberships.sole.branch }
  end
end
