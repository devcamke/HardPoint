# The top plan is now called Unlimited (Plan.all), so shops and invoices on "enterprise" take the new key.
# Invoices are behind row-level security, so the rename switches it off for this transaction.
class RenameEnterprisePlanToUnlimited < ActiveRecord::Migration[8.1]
  def up = rename("enterprise", "unlimited")
  def down = rename("unlimited", "enterprise")

  private
    def rename(from, to)
      safety_assured do
        execute "SET LOCAL app.bypass_rls = 'on'"
        %w[ accounts billing_invoices ].each { execute "UPDATE #{_1} SET plan = #{quote(to)} WHERE plan = #{quote(from)}" }
      end
    end
end
