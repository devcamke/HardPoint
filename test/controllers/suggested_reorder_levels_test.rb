require "test_helper"

class SuggestedReorderLevelsTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)

  setup do
    @main = acme { branches(:acme_main) }
    acme do
      Current.set(account: accounts(:acme)) do
        # Cement sells 4 bags a day here; its reorder level of 20 is more than a three-day delivery needs (12).
        30.times do |days_ago|
          sold = products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -4, reason: "sold")
          StockMovement.where(id: sold.id).update_all(created_at: days_ago.days.ago)
        end
      end
    end
  end

  test "the reorder list suggests a level from the branch's sales, and Use sets it for that branch" do
    sign_in_as users(:amina)
    get reorder_list_path, params: { branch_id: @main.id }
    assert_select "button", /suggest 12 · Use/

    cement = acme { products(:acme_cement) }
    patch product_reorder_level_path(cement), params: { branch_id: @main.id, reorder_level: 12, return_to: "reorder_list" }
    assert_redirected_to reorder_list_path(branch_id: @main.id)
    assert_equal 12, acme { cement.stock_levels.find_by!(branch: @main).reorder_level }
  end

  test "every suggestion at a branch is used in one go, by those who look after the catalogue" do
    sign_in_as users(:carl)
    post suggested_reorder_levels_path, params: { branch_id: @main.id }
    assert_response :forbidden

    sign_in_as users(:amina)
    post suggested_reorder_levels_path, params: { branch_id: @main.id }
    assert_redirected_to reorder_list_path(branch_id: @main.id)
    assert_equal 12, acme { products(:acme_cement).stock_levels.find_by!(branch: @main).reorder_level }
  end
end
