# The simulator's stand-in for Airtel calling back once the customer has answered the prompt.
class Airtel::SimulatedCallbackJob < ApplicationJob
  def perform(merchant, transaction_id, msisdn)
    merchant.receive_callback(self.class.payload(transaction_id, msisdn))
  end

  def self.payload(transaction_id, msisdn)
    declined = msisdn.end_with?("0000")
    { "transaction" => { "id" => transaction_id, "status_code" => declined ? "TF" : "TS",
      "airtel_money_id" => ("MP#{Time.current.strftime("%y%m%d")}.#{SecureRandom.random_number(10**4).to_s.rjust(4, "0")}.A#{SecureRandom.alphanumeric(5).upcase}" unless declined),
      "message" => declined ? "Transaction declined by the customer" : "Paid" } }
  end
end
