# Gap-free numbering per branch (receipts, returns). The counter row is locked for the rest of the
# surrounding transaction, so two tills can't take the same number, and a rolled-back sale gives
# its number back.
class DocumentSequence < ApplicationRecord
  include AccountOwned

  belongs_to :branch

  def self.next_number(branch, kind)
    sequence = create_or_find_by!(account: branch.account, branch: branch, kind: kind)
    sequence.lock!
    sequence.increment!(:last_number)
    sequence.last_number
  end
end
