class Current < ActiveSupport::CurrentAttributes
  attribute :account, :session
  delegate :user, :membership, to: :session, allow_nil: true

  resets { Account.release_isolation }

  def account=(account)
    super
    Account.isolate_to(account)
  end
end
