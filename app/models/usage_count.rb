# Daily counts of the shortcuts a shop uses (docs/SIMPLIFY.md, "How we'll know it worked"): search results
# opened, Home's "Needs you today" buttons and quick actions, drafting every reorder at once, and so on.
# Names come from a fixed list, so a link can't fill the table with made-up ones.
class UsageCount < ApplicationRecord
  include AccountOwned

  # search:<group>, home:<task or start_selling>, quick:<action>, or a named shortcut.
  NAME = /\A(?:search:(?:products|customers|suppliers|documents|pages|actions)|home:[a-z_]{1,40}|quick:[a-z_]{1,40}|
              reorder_draft_all|product_add_another|till_opened_straight)\z/x

  def self.record(name, account: Current.account)
    return unless account && name.to_s.match?(NAME)

    # In a savepoint, so a count that fails can't spoil a transaction the caller is in.
    transaction(requires_new: true) do
      upsert_all([ { account_id: account.id, name: name.to_s, on: Date.current, count: 1 } ],
        unique_by: %i[ account_id name on ], on_duplicate: Arel.sql("count = usage_counts.count + 1, updated_at = CURRENT_TIMESTAMP"),
        record_timestamps: true)
    end
  rescue ActiveRecord::ActiveRecordError => error
    Rails.error.report(error, handled: true) # counting must never get in the way of the page
  end
end
