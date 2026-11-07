require "test_helper"

class Account::FeaturesTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
  end

  test "new shops start with the common features, and unknown keys are dropped" do
    assert_equal [ "deliveries" ], Account.new.features

    @account.update!(features: [ "jobs", "jobs", "teleporter", :promotions ])
    assert_equal %w[ jobs promotions ], @account.features
    assert @account.feature?(:jobs)
    assert_not @account.feature?(:tool_hire)
  end

  test "a feature that's quiet can be switched off, and back on with its records intact" do
    job = @account.jobs.create!(customer: customers(:acme_contractor), name: "Kilimani flats")

    @account.update!(features: @account.features - [ "jobs" ])
    assert_not @account.feature?(:jobs)
    assert @account.jobs.exists?(job.id)

    @account.update!(features: @account.features + [ "jobs" ])
    assert @account.feature?(:jobs)
  end

  test "a running promotion keeps Promotions switched on until it ends" do
    promotion = @account.promotions.create!(name: "Cement week", kind: "percent_off", percent_off: 5, starts_on: Date.current, ends_on: Date.current + 7,
      product_ids: [ products(:acme_cement).id ])

    assert_not @account.update(features: @account.features - [ "promotions" ])
    assert_match "Promotions can't be switched off: A promotion is running. End it first.", @account.errors.full_messages.to_sentence

    promotion.update!(active: false)
    assert @account.reload.update(features: @account.features - [ "promotions" ])
  end

  test "products that record batches or serial numbers keep those features on" do
    products(:acme_nails).update!(serialized: true)

    assert_not @account.update(features: @account.features - [ "serial_numbers" ])
    assert_equal "A product records serial numbers. Untick that on it first.", @account.reload.feature_in_use_reason(:serial_numbers)
  end

  test "an existing shop keeps every feature it has records for" do
    assert_empty @account.features_in_use - Account::Features::KEYS
    assert_not_includes @account.features_in_use, "jobs"

    @account.jobs.create!(customer: customers(:acme_contractor), name: "Kilimani flats")
    assert_includes @account.features_in_use, "jobs"
  end
end
