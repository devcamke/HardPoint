# Jobs run with the account that was current when they were enqueued, so that
# record arguments (Global IDs) can be loaded through row-level security.
module AccountAwareJob
  def serialize
    super.merge("account_id" => Current.account&.id)
  end

  def deserialize(job_data)
    super
    @account_id = job_data["account_id"]
  end

  def perform_now
    if @account_id && Current.account&.id != @account_id
      Current.set(account: Account.find(@account_id)) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  prepend AccountAwareJob
end
