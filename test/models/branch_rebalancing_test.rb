require "test_helper"

class BranchRebalancingTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @main, @yard = branches(:acme_main), branches(:acme_yard)
  end

  def moves = BranchRebalancing.new(accounts(:acme)).moves

  test "a branch at its reorder level is sent what another can spare, leaving that one enough of its own" do
    # Cement reorders at 20: the yard's 10 is short of the 40 it aims for; the main branch keeps 40 of its 50.
    move = moves.find { _1.product == products(:acme_cement) }
    assert_equal [ @main, @yard, 10, "at or below its reorder level" ], [ move.from_branch, move.to_branch, move.quantity, move.reason ]
    assert_equal 70000 * 10, move.value_cents
  end

  test "what the till turned away is a need too, and nothing moves from a branch that's short itself" do
    accounts(:acme).stock_refusals.create!(branch: @yard, product: products(:acme_screws), quantity: 200, on_hand: 0)
    move = moves.find { _1.product == products(:acme_screws) }
    assert_equal [ @main, @yard, 200 ], [ move.from_branch, move.to_branch, move.quantity ], "the most a customer asked for"
    assert_equal "turned away 1 time at the till", move.reason

    products(:acme_cement).update!(reorder_level: 40) # now the main branch is short as well
    assert_nil moves.find { _1.product == products(:acme_cement) }
  end

  test "a shop with fewer than two branches has nothing to move" do
    assert_empty BranchRebalancing.new(Account.new).moves
  end
end
