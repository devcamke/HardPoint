require "test_helper"

class ProductImageTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "a product's photo must be an image of a sensible size" do
    product = products(:acme_nails)
    product.image.attach(io: file_fixture("signed-note.png").open, filename: "nails.png", content_type: "image/png")
    assert product.valid?

    product.image.attach(io: StringIO.new("<svg onload=alert(1)>"), filename: "x.svg", content_type: "image/svg+xml")
    assert_not product.valid?
    assert_includes product.errors[:image], "must be a photo (JPEG, PNG, WebP or GIF)"
  end
end
