class AddExpiryAndTextsToLoyalty < ActiveRecord::Migration[8.1]
  def change
    # Points can expire a number of months after the month they're earned in; nil means never.
    # Points already held when expiry is turned on (or shortened) count from that day.
    add_column :loyalty_programs, :expiry_months, :integer
    add_column :loyalty_programs, :expiry_starts_on, :date
    # Text customers what they earned, and warn them before points expire.
    add_column :loyalty_programs, :text_points, :boolean, null: false, default: false
  end
end
