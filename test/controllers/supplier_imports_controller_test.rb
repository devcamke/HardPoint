require "test_helper"

class SupplierImportsControllerTest < ActionDispatch::IntegrationTest
  def upload(csv)
    file = Tempfile.new([ "suppliers", ".csv" ]).tap { _1.write(csv); _1.rewind }
    post supplier_import_path, params: { supplier_import: { file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "creditors.csv") } }
  end

  test "the owner imports suppliers and sees what came across" do
    sign_in_as users(:amina)
    get suppliers_path
    assert_select "a[href=?]", new_supplier_import_path
    get new_supplier_import_path
    assert_select "a[href='/supplier-import-template.csv']"

    upload "name,balance\nSteel Masters Ltd,62500\n"
    assert_response :success
    assert_match "KES 62,500.00 owed by you in all", response.body

    steel = Account.without_isolation { Supplier.find_by!(name: "Steel Masters Ltd") }
    get supplier_path(steel)
    assert_select "td a", "OPENING BALANCE"
    get supplier_invoice_path(Account.without_isolation { steel.supplier_invoices.sole })
    assert_response :success
  end

  test "problems are listed by line and nothing is imported" do
    sign_in_as users(:amina)
    assert_no_difference -> { Account.without_isolation { Supplier.count } } do
      upload "name,balance\nSteel Masters Ltd,lots\n"
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert] td", "2"
  end

  test "it's the owner's to do" do
    sign_in_as users(:carl)
    get new_supplier_import_path
    assert_response :forbidden
  end
end
