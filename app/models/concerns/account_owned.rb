# For records that belong to a shop. Row-level security keeps other shops' rows invisible,
# but Postgres foreign keys don't consult it, so references are also checked here: a record
# may only point at rows of its own shop.
module AccountOwned
  extend ActiveSupport::Concern

  included do
    belongs_to :account, default: -> { Current.account }
  end

  class_methods do
    def validates_same_account(*association_names)
      validate do
        association_names.each do |name|
          foreign_key = self.class.reflect_on_association(name).foreign_key
          next if self[foreign_key].blank?

          record = public_send(name)
          errors.add name, "must belong to this shop" if record.nil? || record.account_id != account_id
        end
      end
    end
  end
end
