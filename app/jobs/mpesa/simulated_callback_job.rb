# The simulator's stand-in for Safaricom calling back once the customer has answered the prompt.
class Mpesa::SimulatedCallbackJob < ApplicationJob
  def perform(shortcode, checkout_request_id, phone, amount)
    shortcode.receive_stk_callback(self.class.payload(checkout_request_id, phone, amount))
  end

  def self.payload(checkout_request_id, phone, amount)
    if phone.end_with?("0000")
      { "Body" => { "stkCallback" => { "MerchantRequestID" => "sim", "CheckoutRequestID" => checkout_request_id, "ResultCode" => 1032,
        "ResultDesc" => "Request cancelled by user" } } }
    else
      { "Body" => { "stkCallback" => { "MerchantRequestID" => "sim", "CheckoutRequestID" => checkout_request_id, "ResultCode" => 0,
        "ResultDesc" => "The service request is processed successfully.", "CallbackMetadata" => { "Item" => [
          { "Name" => "Amount", "Value" => amount }, { "Name" => "MpesaReceiptNumber", "Value" => "S#{SecureRandom.alphanumeric(9).upcase}" },
          { "Name" => "TransactionDate", "Value" => Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S").to_i },
          { "Name" => "PhoneNumber", "Value" => phone.to_i } ] } } } }
    end
  end
end
