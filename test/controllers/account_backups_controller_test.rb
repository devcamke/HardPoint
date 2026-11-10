require "test_helper"

class AccountBackupsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def backups = Account.without_isolation { @account.account_backups.reload.to_a }

  test "an owner backs up now, downloads it and deletes it" do
    get account_data_path
    assert_select "#backups", /Backups/
    assert_select "#backups", /No backups yet/

    perform_enqueued_jobs(only: AccountBackupJob) { post account_backups_path }
    assert_redirected_to account_data_path(anchor: "backups")
    backup = backups.last
    assert Account.without_isolation { backup.reload.succeeded? }
    assert backup.manual?

    get account_data_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(backup)}", /Ready/

    get account_backup_path(backup)
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert response.body.start_with?("PK")

    delete account_backup_path(backup)
    assert Account.without_isolation { backup.reload.expired? }
    get account_backup_path(backup)
    assert_redirected_to account_data_path(anchor: "backups")

    actions = Account.without_isolation { @account.account_events.order(:id).last(3).map(&:action) }
    assert_equal %w[ backup_requested backup_downloaded backup_deleted ], actions
  end

  test "HardPoint support signed in as the owner can't download a backup" do
    perform_enqueued_jobs(only: AccountBackupJob) { post account_backups_path }
    Account.without_isolation { Session.where(user: users(:amina)).update_all(impersonator_id: users(:ada).id, expires_at: 1.hour.from_now) }

    get account_backup_path(backups.last)
    assert_redirected_to account_data_path(anchor: "backups")
    assert_equal "Not while HardPoint support is signed in as you.", flash[:alert]
  end

  test "a second backup isn't started while one is being made" do
    post account_backups_path
    assert_no_difference -> { backups.size } do
      post account_backups_path
    end
    assert_match "already", flash[:alert]
  end

  test "owners choose the schedule, how many to keep and which emails they get" do
    patch backup_schedule_path, params: { account: { backup_frequency: "weekly", backups_kept: 4, backup_notifications: "failures" } }
    acme = Account.without_isolation { @account.reload }
    assert_equal [ "weekly", 4, "failures" ], [ acme.backup_frequency, acme.backups_kept, acme.backup_notifications ]

    patch backup_schedule_path, params: { account: { backup_frequency: "hourly", backups_kept: 99 } }
    assert_match "Backup frequency", flash[:alert]
    assert_equal "weekly", Account.without_isolation { @account.reload.backup_frequency }
  end

  test "works while the shop is read-only" do
    Account.without_isolation { @account.update!(subscription_status: "read_only") }
    assert_difference -> { backups.size } do
      post account_backups_path
    end
  end

  test "only owners" do
    sign_out
    sign_in_as users(:carl), account: @account
    post account_backups_path
    assert_response :forbidden
    patch backup_schedule_path, params: { account: { backup_frequency: "off" } }
    assert_response :forbidden
  end

  test "another shop's backup can't be downloaded" do
    other = Account.without_isolation do
      Current.set(account: accounts(:bolt)) { accounts(:bolt).account_backups.create!(kind: "scheduled", period: "daily:x") }
    end
    get account_backup_path(other)
    assert_response :not_found
  end
end
