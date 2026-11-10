# Records that use up a plan's allowance (branches, tills, staff) can't be added past it, add-ons included.
module CountsTowardsPlan
  extend ActiveSupport::Concern

  class_methods do
    # counting: the attribute that says whether a record uses up the allowance (e.g. only active tills).
    # It's checked when the record starts counting: when it's added, or when it's switched back on.
    def counts_towards_plan(resource, counting: nil)
      validate if: -> { counting ? public_send(counting) && (new_record? || will_save_change_to_attribute?(counting)) : new_record? } do
        plan_account = account || Current.account
        if plan_account && !plan_account.room_for?(resource)
          plan = plan_account.subscription_plan
          more = plan.add_on_cents(resource) ? "Add #{Plan::NOUNS.fetch(resource).pluralize(2)} or upgrade" : "Upgrade"
          errors.add :base, "Your #{plan.name} plan allows #{Plan.allowance(plan_account.limit(resource), resource)}. #{more} on the Billing page to add more."
        end
      end
    end
  end
end
