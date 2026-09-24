require "test_helper"

class HireControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    @mixer = Account.without_isolation do
      Current.set(account: @account) { @account.hire_items.create!(branch: branches(:acme_main), name: "Concrete mixer", asset_tag: "MIX-01", daily_rate: "1500", deposit: "5000") }
    end
    sign_in_as users(:amina), account: @account
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  def acme(&) = Account.without_isolation(&)

  test "hire out, take the deposit, bring it back, settle at the till" do
    get new_hire_agreement_path
    assert_select "#hire_item_#{@mixer.id}"

    post hire_agreements_path, params: { hire_item_ids: [ @mixer.id ], hire_agreement: { customer_name: "Peter Kamau", customer_phone: "0722 111 222",
      id_number: "23456789", site: "Ruiru", due_back_at: 2.days.from_now.strftime("%Y-%m-%dT%H:%M"), branch_id: branches(:acme_main).id } }
    agreement = acme { @account.hire_agreements.last }
    assert_redirected_to hire_agreement_path(agreement)
    follow_redirect!
    assert_select "h1", /Hire #{acme { agreement.reference }}/
    assert acme { @mixer.reload.on_hire? }

    get hire_agreement_document_path(agreement)
    assert_equal "application/pdf", response.media_type

    get hire_items_path
    assert_select "##{dom_id(@mixer)}", /On hire/

    post hire_agreement_return_path(agreement), params: { returns: { acme { agreement.lines.first.id } => { back: "1", condition_note: "Fine" } } }
    assert_redirected_to hire_agreement_path(agreement)
    assert acme { agreement.reload.returned? }

    post customer_order_collection_path(acme { agreement.customer_order })
    assert_redirected_to pos_path
  end

  test "extending and cancelling" do
    agreement = acme do
      Current.set(account: @account) do
        HireAgreement.hire_out(branch: branches(:acme_main), customer: customers(:acme_contractor), items: [ @mixer ], due_back_at: 1.day.from_now)
      end
    end
    post hire_agreement_extension_path(agreement), params: { due_back_at: 5.days.from_now.strftime("%Y-%m-%dT%H:%M") }
    assert acme { agreement.reload.due_back_at } > 4.days.from_now

    post hire_agreement_cancellation_path(agreement)
    assert acme { agreement.reload.cancelled? }
    assert acme { @mixer.reload.available? }
  end

  test "managers keep the tool list; cashiers hire out but can't change it" do
    post hire_items_path, params: { hire_item: { name: "Plate compactor", asset_tag: "cmp-01", daily_rate: "2500", deposit: "8000", branch_id: branches(:acme_main).id } }
    assert_equal "CMP-01", acme { @account.hire_items.last.asset_tag }

    sign_out
    sign_in_as users(:carl), account: @account
    get hire_items_path
    assert_response :success
    post hire_items_path, params: { hire_item: { name: "X", asset_tag: "X", daily_rate: "1" } }
    assert_response :forbidden
  end

  test "another shop's hires and tools can't be reached" do
    other = acme do
      Current.set(account: accounts(:bolt)) do
        tool = accounts(:bolt).hire_items.create!(branch: branches(:bolt_main), name: "Drill", asset_tag: "D1", daily_rate: "500")
        HireAgreement.hire_out(branch: branches(:bolt_main), customer: customers(:bolt_customer), items: [ tool ], due_back_at: 1.day.from_now)
      end
    end
    get hire_agreement_path(other)
    assert_response :not_found
    get edit_hire_item_path(other.hire_items.first)
    assert_response :not_found
  end
end
