require "test_helper"

class HireTermsTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    Current.account = @account
    @mixer = @account.hire_items.create!(branch: branches(:acme_main), name: "Concrete mixer", asset_tag: "MIX-01", daily_rate: "1500", deposit: "5000")
  end

  def hire_out
    HireAgreement.hire_out(branch: branches(:acme_main).reload, customer: customers(:acme_contractor), items: [ @mixer.reload ], due_back_at: 1.day.from_now)
      .tap { |agreement| @mixer.reload.update!(status: "available") if agreement.persisted? }
  end

  test "a shop uses the standard terms until it writes its own" do
    assert_not @account.own_hire_terms?
    assert_equal Account::HireTerms::STANDARD, @account.hire_terms_list
  end

  test "own terms are one per line, with typed numbers and bullets left off" do
    @account.update!(hire_terms: "1. Tools stay ours.\n\n  - Pay for damage.  \n3) Return by 5pm.")

    assert @account.own_hire_terms?
    assert_equal [ "Tools stay ours.", "Pay for damage.", "Return by 5pm." ], @account.hire_terms_list
  end

  test "saving the standard terms unchanged keeps the shop on the standard terms" do
    @account.update!(hire_terms: Account::HireTerms::STANDARD.join("\n"))
    assert_not @account.own_hire_terms?
  end

  test "terms must fit on the agreement" do
    assert_not @account.update(hire_terms: Array.new(21) { "Term #{_1}" }.join("\n"))
    assert_includes @account.errors[:hire_terms], "can have at most 20 terms"

    assert_not @account.update(hire_terms: "Short\n#{"x" * 601}")
    assert_includes @account.errors[:hire_terms], "term 2 is too long (at most 600 characters)"
  end

  test "an agreement keeps the terms it was made under, whatever the shop changes later" do
    @account.update!(hire_terms: "Tools stay ours.\nPay for damage.")
    signed = hire_out
    assert signed.persisted?, signed.errors.full_messages.to_sentence

    @account.update!(hire_terms: "Completely new terms.")
    later = hire_out

    assert_equal [ "Tools stay ours.", "Pay for damage." ], signed.reload.terms_list
    assert_equal [ "Tools stay ours.", "Pay for damage." ], HireAgreementPdf.new(signed).terms
    assert_equal [ "Completely new terms." ], HireAgreementPdf.new(later.reload).terms
    assert HireAgreementPdf.new(signed).render.start_with?("%PDF")
  end

  test "agreements from before shops had their own terms print the standard ones" do
    agreement = hire_out
    agreement.update_columns(terms: nil)

    assert_equal Account::HireTerms::STANDARD, HireAgreementPdf.new(agreement.reload).terms
  end
end
