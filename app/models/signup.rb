# Creates a new shop: its account, the owner's membership and a first branch.
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :shop_name, :string
  attribute :subdomain, :string
  attribute :owner_name, :string
  attribute :email_address, :string
  attribute :password, :string

  attr_reader :account

  validates :shop_name, :subdomain, :owner_name, :email_address, :password, presence: true
  validates :password, length: { minimum: 10 }, allow_blank: true, unless: :existing_user
  validate :existing_user_password_matches

  def save
    return false unless valid?

    Account.transaction do
      @account = Account.create!(name: shop_name, subdomain: subdomain)

      Current.set(account: @account) do
        @account.memberships.create!(user: owner, role: :owner)
        @account.branches.create!(name: "Main branch")
      end
    end

    true
  rescue ActiveRecord::RecordInvalid => invalid
    invalid.record.errors.each do |error|
      errors.add form_attribute_for(invalid.record, error.attribute), error.message
    end
    false
  end

  def save!
    save || raise(ActiveModel::ValidationError, self)
  end

  private
    def owner
      existing_user || User.create!(name: owner_name, email_address: email_address, password: password)
    end

    def existing_user
      @existing_user ||= User.find_by(email_address: email_address.to_s.strip.downcase)
    end

    def form_attribute_for(record, attribute)
      case [ record.class.name, attribute ]
      in [ "Account", :name ] then :shop_name
      in [ "User", :name ] then :owner_name
      in [ _, attribute ] if self.class.attribute_names.include?(attribute.to_s) then attribute
      else :base
      end
    end

    def existing_user_password_matches
      if existing_user && !existing_user.authenticate(password)
        errors.add :email_address, "already has a HardPoint login — enter that password to add a new shop"
      end
    end
end
