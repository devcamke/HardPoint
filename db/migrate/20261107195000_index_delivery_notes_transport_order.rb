class IndexDeliveryNotesTransportOrder < ActiveRecord::Migration[8.1]
  def change
    add_index :delivery_notes, :transport_order_id, where: "transport_order_id IS NOT NULL"
  end
end
