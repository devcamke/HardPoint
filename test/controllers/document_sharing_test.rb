require "test_helper"

# Receipts, quotes, invoices and credit notes can be shared or saved as pictures (made in the browser from their PDFs).
class DocumentSharingTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)

  setup do
    sign_in_as users(:amina)
    acme do
      Current.set(account: accounts(:acme), session: accounts(:acme).sessions.create!(user: users(:amina))) do
        @sale = shifts(:acme_front_open).current_sale
        @sale.change_customer(customers(:acme_contractor))
        @sale.add(products(:acme_nails), quantity: 4)
        @sale.pay(tender: "cash", tendered_cents: 1000_00)
        @return = @sale.sale_returns.create!(account: accounts(:acme), branch: @sale.branch, shift: shifts(:acme_front_open), refund_method: "cash", reason: "Wrong size",
          lines_attributes: [ { sale_line_id: @sale.lines.sole.id, quantity: 1, restock: true } ])
        @quote = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
          lines_attributes: [ { product: products(:acme_nails), quantity: 2 } ])
      end
    end
  end

  test "a receipt and a credit note come as PDFs, the receipt the width of the till roll" do
    get sale_receipt_path(@sale, format: :pdf)
    assert_equal "application/pdf", response.media_type
    assert_match %r{/MediaBox \[0 0 226.77}, response.body, "80 mm wide"

    get return_path(@return, format: :pdf)
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
  end

  test "the sale, its return and an order each have a share menu pointing at their PDF" do
    get sale_path(@sale)
    assert_select "[data-controller~=document-share][data-document-share-pdf-value='#{sale_receipt_path(@sale, format: :pdf)}']"
    assert_select "[data-controller~=document-share][data-document-share-pdf-value='#{sale_invoice_path(@sale)}']"
    assert_select "[data-document-share-worker-value*='pdfjs.worker']"
    assert_select "button", /Share as a picture/

    get return_path(@return)
    assert_select "[data-document-share-pdf-value='#{return_path(@return, format: :pdf)}']"

    get customer_order_path(@quote)
    assert_select "[data-document-share-pdf-value='#{customer_order_path(@quote, format: :pdf)}']"
  end

  test "pdf.js is in the import map but never preloaded" do
    get sale_path(@sale)
    assert_match %r{"pdfjs-dist": ?"/assets/pdfjs\.min-}, response.body
    assert_no_match %r{modulepreload[^>]*pdfjs}, response.body
  end
end
