# Closing a shop: an owner asks (with their password), the shop goes read-only and only owners can
# sign in, and 30 days later its data is deleted for good, unless an owner cancels first. The
# platform keeps a tombstone (AccountDeletion) with the invoices it issued, for its tax records.
module Account::Closure
  extend ActiveSupport::Concern

  GRACE = 30.days

  included do
    belongs_to :deletion_requested_by, class_name: "User", optional: true
    has_many :account_exports, dependent: :delete_all

    scope :due_for_deletion, -> { where(deletion_scheduled_for: ..Time.current) }
  end

  class_methods do
    # Daily: deletes the shops whose 30 days are up.
    def purge_closed
      due_for_deletion.find_each(&:purge!)
    end
  end

  def closing?
    deletion_scheduled_for.present?
  end

  def request_closure(by:, password:)
    unless memberships.find_by(user: by)&.owner?
      errors.add :base, "Only an owner can close the shop"
      return false
    end
    unless by.authenticate(password.to_s)
      errors.add :base, "That password isn't right"
      return false
    end

    update!(deletion_scheduled_for: GRACE.from_now, deletion_requested_by: by)
    track_event "closure_requested", creator: by, deletion_on: deletion_scheduled_for.to_date.iso8601
    AccountClosuresMailer.with(account: self).scheduled.deliver_later
    true
  end

  def cancel_closure(by:)
    return false unless closing?

    update!(deletion_scheduled_for: nil, deletion_requested_by: nil)
    track_event "closure_cancelled", creator: by
  end

  # Deletes every row the shop owns, its files, and staff logins no other shop uses. Foreign keys
  # are deferred so rows can go in any order; they're all checked when the transaction commits.
  def purge!
    blob_ids = []

    Account.without_isolation do
      transaction do
        AccountDeletion.record(self)
        blob_ids = attached_blob_ids
        ActiveStorage::Attachment.where(blob_id: blob_ids).delete_all
        member_ids = memberships.pluck(:user_id)

        self.class.connection.execute "SET CONSTRAINTS ALL DEFERRED"
        tenant_tables.each do |table|
          self.class.connection.execute "DELETE FROM #{self.class.connection.quote_table_name(table)} WHERE account_id = #{Integer(id)}"
        end
        self.class.where(id: id).delete_all
        self.class.connection.execute "SET CONSTRAINTS ALL IMMEDIATE"

        delete_orphaned_users(member_ids)
      end
    end

    ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later)
  end

  private
    def tenant_tables
      self.class.connection.select_values(<<~SQL)
        SELECT table_name FROM information_schema.columns
        WHERE column_name = 'account_id' AND table_schema = current_schema() ORDER BY table_name
      SQL
    end

    def attached_blob_ids
      ActiveStorage::Attachment.where(record_type: "Product", record_id: products.select(:id))
        .or(ActiveStorage::Attachment.where(record_type: "DeliveryNote", record_id: delivery_notes.select(:id)))
        .or(ActiveStorage::Attachment.where(record_type: "AccountExport", record_id: account_exports.select(:id)))
        .pluck(:blob_id)
    end

    # A login goes with the shop unless it's a platform admin, belongs to another shop, or another
    # shop's records still name it (as a former member who made a sale, say).
    def delete_orphaned_users(user_ids)
      User.where(id: user_ids, admin: false).where.not(id: Membership.select(:user_id)).find_each do |user|
        self.class.transaction(requires_new: true) { User.where(id: user.id).delete_all }
      rescue ActiveRecord::InvalidForeignKey
        next
      end
    end
end
