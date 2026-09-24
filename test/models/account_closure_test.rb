require "test_helper"

class AccountClosureTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
  end

  test "an owner closes the shop with their password; it's locked, and can be reopened" do
    assert_not @account.request_closure(by: users(:carl), password: "password")
    assert_not @account.request_closure(by: users(:amina), password: "wrong")
    assert_match "password isn't right", @account.errors.full_messages.to_sentence

    assert_enqueued_email_with AccountClosuresMailer, :scheduled, params: { account: @account } do
      assert @account.request_closure(by: users(:amina), password: "password")
    end
    assert @account.closing?
    assert @account.locked?
    assert_in_delta 30.days.from_now, @account.deletion_scheduled_for, 1.minute

    @account.cancel_closure(by: users(:amina))
    assert_not @account.locked?
    assert_equal %w[ closure_requested closure_cancelled ], @account.account_events.where(action: %w[ closure_requested closure_cancelled ]).order(:id).pluck(:action)
  end

  test "30 days on, the shop's data is deleted, and only the platform's tombstone is left" do
    invoice = @account.start_subscription_now
    @account.request_closure(by: users(:amina), password: "password")
    bolt_products = Account.without_isolation { accounts(:bolt).products.count }
    owner_email, cashier_id, other_shop_owner_id = users(:amina).email_address, users(:carl).id, users(:bob).id
    Current.reset

    travel 31.days do
      Account.purge_closed
    end

    Account.without_isolation do
      assert_not Account.exists?(@account.id)
      assert_equal 0, Product.where(account_id: @account.id).count
      assert_equal 0, Sale.where(account_id: @account.id).count
      assert_equal 0, Event.where(account_id: @account.id).count
      assert_equal bolt_products, accounts(:bolt).products.count

      deletion = AccountDeletion.find_by!(former_account_id: @account.id)
      assert_equal [ "acme", owner_email ], [ deletion.subdomain, deletion.requested_by_email ]
      assert_equal [ invoice.number ], deletion.billing_invoices.map { _1["number"] }

      assert_not User.exists?(cashier_id), "a login only this shop used goes"
      assert User.exists?(other_shop_owner_id), "another shop's logins stay"
    end
  end

  test "shops not yet due aren't touched" do
    @account.request_closure(by: users(:amina), password: "password")
    Current.reset
    travel 29.days do
      Account.purge_closed
    end
    assert Account.exists?(@account.id)
  end
end
