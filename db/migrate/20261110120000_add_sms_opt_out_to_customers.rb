class AddSmsOptOutToCustomers < ActiveRecord::Migration[8.1]
  def change
    # A customer who has asked not to be texted. Every outbound text checks it, whatever the text is about.
    add_column :customers, :sms_opt_out, :boolean, null: false, default: false
  end
end
