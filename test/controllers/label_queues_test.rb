require "test_helper"

# The shelf-label queue: products whose price or name changed, or that are new, wait for a new label.
class LabelQueuesTest < ActionDispatch::IntegrationTest
  setup do
    in_acme { accounts(:acme).products.labels_printed } # fixtures arrive as new products; start with every label on the shelf
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme), user: users(:amina)) { yield } }

  test "a price change queues a label, keeping the price the shelf still shows" do
    cement = products(:acme_cement)
    in_acme do
      cement.update!(price_cents: 900_00)
      cement.update!(price_cents: 950_00) # the shelf still shows the first price
      assert_equal [ true, 800_00 ], [ cement.reload.label_due_at.present?, cement.label_old_price_cents ]
      assert cement.shelf_price_wrong?

      products(:acme_nails).update!(reorder_level: 7) # nothing a label shows
      assert_nil products(:acme_nails).reload.label_due_at
    end
  end

  test "bulk price changes and imports, which skip callbacks, queue labels too" do
    in_acme do
      accounts(:acme).products.where(id: products(:acme_pipe).id).update_all(price_cents: 1300_00)
      assert products(:acme_pipe).reload.label_due_at
      assert_equal 1200_00, products(:acme_pipe).label_old_price_cents
    end
  end

  test "Stock › Labels lists what's waiting, prints it, and marks it done" do
    in_acme { products(:acme_cement).update!(price_cents: 900_00) }
    sign_in_as users(:amina)

    get products_path
    assert_select "nav [aria-label='Stock menu'] a[href=?]", label_queue_path, text: "Labels"

    get label_queue_path
    assert_select "td", /Bamburi cement 50kg/
    assert_select "td span.text-red-700", "Shelf shows KES 800.00"
    assert_select "button[formaction=?][formtarget=_blank]", labels_path

    get labels_path(copies: { products(:acme_cement).id => 2 }, format: "roll")
    assert_response :success

    patch label_queue_path, params: { product_ids: [ products(:acme_cement).id ] }
    follow_redirect!
    assert_select "p", /1 label marked as on the shelf/
    assert_select "p", /Every shelf label is up to date/
    assert_nil in_acme { products(:acme_cement).reload.label_due_at }
  end

  test "a new product waits for its first label; cashiers can look but not mark labels done" do
    product = in_acme { accounts(:acme).products.create!(name: "Garden tap", sku: "TAP-1", unit: units(:acme_piece), price_cents: 1200_00) }
    sign_in_as users(:carl)
    get label_queue_path
    assert_select "td", /Garden tap/
    assert_select "td", /New product/
    assert_select "input[type=submit][value*=done]", count: 0

    patch label_queue_path, params: { product_ids: [ product.id ] }
    assert_response :forbidden
  end
end
