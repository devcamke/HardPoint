class AddTransportCharges < ActiveRecord::Migration[8.1]
  def change
    # Transport to the customer's site, charged when the delivery note is made after the sale: it becomes
    # an order for the customer, collected at the till or put on their account like any other.
    add_column :delivery_notes, :transport_charge_cents, :bigint, null: false, default: 0
    add_reference :delivery_notes, :transport_order, foreign_key: { to_table: :customer_orders, deferrable: :immediate }, index: false
  end
end
