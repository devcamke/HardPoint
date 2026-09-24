require "test_helper"

class EtimsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "an owner adds a branch's control unit, sets it up, and signed receipts carry KRA's QR code" do
    get etims_devices_path
    assert_select "a", "Add control unit"

    post etims_devices_path, params: { etims_device: { branch_id: branches(:acme_main).id, environment: "simulator", tin: "p051234567x",
      bhf_id: "00", serial_number: "HP-MAIN-01", default_item_class_code: "5020230500" } }
    assert_redirected_to etims_devices_path
    device = Account.without_isolation { Etims::Device.sole }
    post etims_device_initialization_path(device)
    assert Account.without_isolation { device.reload.initialized? }

    post pos_till_path, params: { register_id: registers(:acme_front).id }
    post pos_lines_path, params: { code: "NAIL-3" }, as: :turbo_stream
    perform_enqueued_jobs(only: Etims::TransmitJob) { post pos_payments_path, params: { tender: "cash" }, as: :turbo_stream }
    sale = Account.without_isolation { Sale.completed.includes(:branch).last }

    get sale_receipt_path(sale)
    assert_select ".receipt", /KRA eTIMS/
    assert_select ".receipt svg path"

    get etims_submissions_path
    assert_select "td", "Sale #{sale.receipt_number}"
  end

  test "refused submissions show why and can be sent again" do
    submission = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        device = accounts(:acme).etims_devices.create!(branch: branches(:acme_main), environment: "simulator", tin: "P051234567X", serial_number: "X1")
        sale = shifts(:acme_front_open).current_sale
        sale.add(products(:acme_nails))
        sale.pay(tender: "cash")
        sale.etims_submission.tap { _1.update!(status: :failed, last_error: "891: Item class code does not exist") }
      end
    end

    get root_path
    assert_select "div", /1 sale refused by KRA eTIMS/
    get etims_submission_path(submission)
    assert_select "p", /Item class code does not exist/

    assert_enqueued_jobs(1, only: Etims::TransmitJob) { post etims_retries_path }
    assert Account.without_isolation { submission.reload.pending? }
  end

  test "cashiers can't manage eTIMS" do
    sign_in_as users(:carl)
    get etims_devices_path
    assert_response :forbidden
    get etims_submissions_path
    assert_response :forbidden
  end
end
