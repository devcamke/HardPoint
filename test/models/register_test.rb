require "test_helper"

class RegisterTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "belongs to one of the shop's branches" do
    register = accounts(:acme).registers.new(name: "Side counter", branch: Account.without_isolation { branches(:bolt_main) })

    assert_not register.valid?
    assert_includes register.errors[:branch], "must be one of this shop's branches"
  end

  test "names are unique within a branch" do
    assert_not accounts(:acme).registers.new(name: "Front counter", branch: branches(:acme_main)).valid?
    assert accounts(:acme).registers.new(name: "Front counter", branch: branches(:acme_yard)).valid?
  end

  test "a branch with tills can't be removed" do
    assert_not branches(:acme_main).destroy
    assert_includes branches(:acme_main).errors.full_messages.to_sentence, "registers"
  end
end
