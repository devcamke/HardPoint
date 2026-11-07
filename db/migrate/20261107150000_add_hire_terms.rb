class AddHireTerms < ActiveRecord::Migration[8.1]
  def change
    # The shop's own terms for hiring out tools, one per line; blank means the standard terms.
    add_column :accounts, :hire_terms, :text
    # The terms an agreement was made under, kept with it so editing the shop's terms never changes
    # what a customer signed. Agreements from before this column print the standard terms they were signed with.
    add_column :hire_agreements, :terms, :text
  end
end
