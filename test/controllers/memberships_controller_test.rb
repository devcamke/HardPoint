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
end
