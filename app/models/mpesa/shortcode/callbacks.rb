# What Safaricom tells a shortcode: answers to prompts (STK callbacks) and payments made straight
# to the Paybill or Till (C2B confirmations). Both are safe to receive more than once.
module Mpesa::Shortcode::Callbacks
  extend ActiveSupport::Concern

  def receive_stk_callback(payload)
    callback = payload.dig("Body", "stkCallback") or return
    request = stk_requests.find_by(checkout_request_id: callback["CheckoutRequestID"]) or return
    details = Array(callback.dig("CallbackMetadata", "Item")).to_h { [ _1["Name"], _1["Value"] ] }

    request.resolve(result_code: callback["ResultCode"].to_s, description: callback["ResultDesc"],
      receipt_number: details["MpesaReceiptNumber"], amount_cents: Monetary.to_cents(details["Amount"]),
      phone: details["PhoneNumber"]&.to_s, transacted_at: parse_time(details["TransactionDate"]), payload: payload)
  end

  def receive_c2b_confirmation(payload)
    return if payload["TransID"].blank? || payload["TransAmount"].blank?

    transaction = Mpesa::Transaction.record(self, source: "c2b", trans_id: payload["TransID"], amount_cents: Monetary.to_cents(payload["TransAmount"]),
      phone: payload["MSISDN"], payer_name: [ payload["FirstName"], payload["MiddleName"], payload["LastName"] ].compact_blank.join(" ").presence,
      bill_reference: payload["BillRefNumber"].presence, transacted_at: parse_time(payload["TransTime"]), payload: payload)
    transaction.auto_match if transaction.previously_new_record?
    transaction
  end

  private
    def parse_time(value)
      Time.find_zone("Nairobi").strptime(value.to_s, "%Y%m%d%H%M%S")
    rescue ArgumentError
      Time.current
    end
end
