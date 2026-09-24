require "test_helper"

class ProductImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "upload, check, confirm, import" do
    file = Rack::Test::UploadedFile.new(StringIO.new("\xEF\xBB\xBFsku,name,price,stock\nNEW-9,Masking tape,95,12\n"), "text/csv", original_filename: "tape.csv")

    perform_enqueued_jobs do
      post product_imports_path, params: { product_import: { file: file, branch_id: branches(:acme_yard).id } }
    end
    import = Account.without_isolation { ProductImport.last }
    assert_redirected_to product_import_path(import)
    assert Account.without_isolation { import.reload.ready? }

    perform_enqueued_jobs { post product_import_run_path(import) }
    assert Account.without_isolation { import.reload.completed? }
    assert_equal 12, Account.without_isolation { Product.find_by!(sku: "NEW-9").stock_at(branches(:acme_yard)) }
  end

  test "a file without the required columns is refused" do
    file = Rack::Test::UploadedFile.new(StringIO.new("foo,bar\n1,2\n"), "text/csv", original_filename: "x.csv")
    post product_imports_path, params: { product_import: { file: file } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation", /needs at least “name” and “price”/
  end

  test "another shop's import can't be seen" do
    bolt_import = Current.set(account: accounts(:bolt)) { accounts(:bolt).product_imports.create!(csv: "name,price\nx,1\n") }
    get product_import_path(bolt_import)
    assert_response :not_found
  end
end
