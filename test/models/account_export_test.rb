require "test_helper"

class AccountExportTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
  end

  def entries(export)
    files = {}
    Zip::File.open_buffer(StringIO.new(export.file.download)) { |zip| zip.each { files[_1.name] = _1.get_input_stream.read } }
    files
  end

  test "a ZIP of every table the shop owns, without secrets or other shops' rows" do
    @account.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator", consumer_secret: "hush")
    export = @account.account_exports.create!
    export.build

    assert export.ready?
    assert_in_delta 7.days.from_now, export.expires_at, 1.minute
    files = entries(export)

    assert_includes files.keys, "README.txt"
    assert_match "Acme Hardware", files["shop.csv"]
    assert_match users(:carl).email_address, files["staff.csv"]

    products = CSV.parse(files.fetch("data/products.csv"), headers: true)
    assert_equal @account.products.count, products.size
    assert_not_includes products.map { _1["sku"] }, products(:bolt_hammer).sku

    assert_not_includes files.fetch("data/mpesa_shortcodes.csv").lines.first, "consumer_secret"
    assert_not_includes files.fetch("data/memberships.csv").lines.first, "pin_digest"
    assert_not files.key?("data/sessions.csv")
  end

  test "the owner is emailed when it's ready, and it expires after a week" do
    export = @account.account_exports.create!
    assert_enqueued_emails(1) { export.build }

    travel 8.days do
      AccountExport.expire_old
      assert export.reload.expired?
      assert_not export.file.attached?
    end
  end
end
