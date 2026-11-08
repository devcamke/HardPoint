class AddTermsAcceptedAtToAccounts < ActiveRecord::Migration[8.1]
  def change
    # When the shop's owner agreed to the terms of service and data processing terms at signup (/terms, /data-processing).
    add_column :accounts, :terms_accepted_at, :datetime
  end
end
