require "test_helper"

class CustomerImportsControllerTest < ActionDispatch::IntegrationTest
  def upload(csv)
    file = Tempfile.new([ "customers", ".csv" ]).tap { _1.write(csv); _1.rewind }
    post customer_import_path, params: { customer_import: { file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "debtors.csv") } }
  end

  test "the owner imports customers and sees what came across" do
    sign_in_as users(:amina)
    get customers_path
    assert_select "a[href=?]", new_customer_import_path
    get new_customer_import_path
    assert_select "a[href='/customer-import-template.csv']"

    upload "name,phone,balance\nOtieno Fundi,0711 222 333,12500\n"
    assert_response :success
    assert_select "dd", "1"
    assert_match "KES 12,500.00 owed to you in all", response.body

    otieno = Account.without_isolation { Customer.find_by!(name: "Otieno Fundi") }
    get customer_path(otieno)
    assert_select "td", "Opening balance"
  end

  test "problems are listed by line and nothing is imported" do
    sign_in_as users(:amina)
    assert_no_difference -> { Account.without_isolation { Customer.count } } do
      upload "name,balance\nOtieno Fundi,lots\n"
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert] td", "2"
    assert_match "isn’t an amount".tr("’", "'"), CGI.unescapeHTML(response.body)
  end

  test "it's the owner's to do" do
    sign_in_as users(:carl)
    get new_customer_import_path
    assert_response :forbidden
    get customers_path
    assert_select "a[href=?]", new_customer_import_path, count: 0
  end
end
