# The owner's first-day checklist, worked out from what the shop has already done, so steps done
# some other way (a branch address added from Settings, say) tick themselves off.
class Onboarding
  Step = Data.define(:key, :title, :done, :optional) do
    alias_method :done?, :done
    alias_method :optional?, :optional
  end

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def steps
    @steps ||= [
      Step.new(:branches, "Name your branches and tills", account.branches.where.not(address: [ nil, "" ]).exists?, false),
      Step.new(:taxes, "Check your tax rates", account.taxes_confirmed_at.present?, false),
      Step.new(:products, "Bring in your products", account.products.exists?, false),
      Step.new(:staff, "Invite your staff", account.memberships.count > 1, false),
      Step.new(:receipt, "Print a test receipt", account.test_receipt_printed_at.present?, false),
      Step.new(:mpesa, "Connect M-Pesa", account.mpesa_shortcodes.exists?, true),
      Step.new(:etims, "Connect KRA eTIMS", account.etims_devices.exists?, true)
    ]
  end

  def required_steps = steps.reject(&:optional?)
  def done_count = required_steps.count(&:done?)
  def ready? = required_steps.all?(&:done?)
  def finished? = account.onboarding_completed_at.present?

  def finish
    account.update!(onboarding_completed_at: Time.current) unless finished?
  end
end
