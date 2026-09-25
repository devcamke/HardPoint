class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Reads that can be a few seconds behind (reports, exports) go to the replica through
  # Account.reading, which carries the shop's row-level security settings across.
  connects_to database: { writing: :primary, reading: :primary_replica }
end
