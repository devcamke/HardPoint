# When someone proved the email address is theirs: by the link sent at sign-up, or by choosing a password from a
# link sent to it. Until then the login is only a claim, and a shop adding that address takes it back.
class AddEmailConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_confirmed_at, :datetime
  end
end
