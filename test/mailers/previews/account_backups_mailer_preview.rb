# Preview all emails at http://localhost:3000/rails/mailers/account_backups_mailer
class AccountBackupsMailerPreview < ActionMailer::Preview
  def succeeded
    AccountBackupsMailer.with(backup: backup(status: "succeeded", byte_size: 18.megabytes,
      manifest: { "tables" => { "products" => 1200, "sales" => 5400 }, "files" => { "files/products/1.jpg" => "x" } }), recipient: owner).succeeded
  end

  def failed
    AccountBackupsMailer.with(backup: backup(status: "failed", attempts: 3, failure: "Timeout"), recipient: owner).failed
  end

  def failed_for_support
    AccountBackupsMailer.with(backup: backup(status: "failed", attempts: 3, failure: "Aws::S3::Errors::ServiceUnavailable: Please reduce your request rate.")).failed_for_support
  end

  private
    def account
      Current.account = Account.first
    end

    def owner
      account.users.where(memberships: { role: "owner" }).first
    end

    def backup(**attributes)
      AccountBackup.new(id: 42, account: account, kind: "scheduled", period: "daily:#{Date.current.iso8601}", created_at: Time.current, started_at: 3.minutes.ago, **attributes)
    end
end
