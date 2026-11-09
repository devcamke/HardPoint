module EventsHelper
  def event_summary(event)
    subject = event.particulars["name"]
    # Entries about records of a kind HardPoint no longer has (tool hire) still read sensibly.
    thing = event.eventable_type.safe_constantize&.model_name&.human&.downcase || event.eventable_type.underscore.humanize(capitalize: false)

    case [ event.eventable_type, event.action ]
    in [ "Account", "created" ] then "opened the shop #{subject}"
    in [ "Account", "updated" ] then "changed shop settings: #{describe_changes(event)}"
    in [ "Session", "signed_in" ] then "signed in#{" from #{event.particulars["ip_address"]}" if event.particulars["ip_address"]}"
    in [ "Session", "switched_in" ] then "switched in at the till with their PIN"
    in [ "Session", "impersonation_started" ] then "was signed in as by HardPoint support (#{event.particulars["administrator"]})"
    in [ "Membership", "created" ] then "added #{subject} as #{event.particulars.dig("role")&.humanize&.downcase || "staff"}"
    in [ "Membership", "updated" ] then "changed #{subject}'s #{describe_changes(event)}"
    in [ "Membership", "destroyed" ] then "removed #{subject}'s access"
    in [ "Membership", "pin_set" ] then "set #{whose(event)} till PIN"
    in [ "Membership", "pin_removed" ] then "removed #{whose(event)} till PIN"
    in [ "Shift", "opened" ] then "opened a shift on #{subject} with #{money(event.particulars["opening_float"])} float"
    in [ "Shift", "closed" ] then "closed the shift on #{subject}: counted #{money(event.particulars["counted"])}, #{variance_words(event.particulars["variance"])}"
    in [ "Sale", "voided" ] then "voided sale #{subject} (#{money(event.particulars["total"])}), approved by #{event.particulars["approver"]}: #{event.particulars["reason"]}" \
      "#{"; #{Sale::Voidable.refund_words(event.particulars["refund_method"], event.particulars["refund_reference"])}" if event.particulars["refund_method"]}"
    in [ "Sale", "completed_without_payment" ] then "completed sale #{subject} with nothing to pay, approved by #{event.particulars["approver"]}"
    in [ "Sale", "returned" ] then "took back items from #{subject}: #{event.particulars["return_number"]}, refunded #{money(event.particulars["total"])} by #{event.particulars["refund_method"].to_s.humanize.downcase}"
    in [ "Sale", "discount_approved" ] then "got a #{event.particulars["percent"]}% discount approved by #{event.particulars["approver"]}"
    in [ "CustomerOrder", "part_collected" ] then "collected part of #{subject} (#{event.particulars["receipt_number"]}); still waiting: #{Array(event.particulars["remaining"]).to_sentence}"
    in [ "CustomerOrder", "deposit_kept" ] then "kept the #{money(event.particulars["amount"])} deposit on #{subject} (#{event.particulars["receipt_number"]}), approved by #{event.particulars["approver"]}#{": #{event.particulars["reason"]}" if event.particulars["reason"].present?}"
    in [ _, "offline_sale_refused" ] then "rang up offline sale #{event.particulars["receipt_number"] || "without a number"} for #{money(event.particulars["total"])}" \
      "#{" on #{subject}" if event.eventable_type == "Register"}#{" at #{Time.zone.parse(event.particulars["happened_at"]).to_fs(:short)}" if event.particulars["happened_at"]}, " \
      "which couldn't be recorded: #{event.particulars["error"]}. The money is in the drawer; ring it up by hand"
    in [ "Membership", "approval_pin_set" ] then "set their approval PIN"
    in [ "Membership", "two_factor_reset" ] then "reset #{subject}'s two-factor sign-in#{by_platform(event)}"
    in [ "PurchaseOrder", "sent" ] then "sent purchase order #{subject} to #{event.particulars["supplier"]} (#{money(event.particulars["total"])})"
    in [ "PurchaseOrder", "cancelled" ] then "cancelled purchase order #{subject}"
    in [ "GoodsReceipt", "received" ] then "received #{subject} from #{event.particulars["supplier"]}#{" for #{event.particulars["purchase_order"]}" if event.particulars["purchase_order"]} (#{money(event.particulars["total"])})"
    in [ "SupplierInvoice", "recorded" ] then "recorded invoice #{subject} (#{money(event.particulars["total"])})"
    in [ "Supplier", "paid" ] then "paid #{subject} #{money(event.particulars["amount"])} by #{event.particulars["payment_method"].to_s.humanize.downcase}"
    in [ "ProductImport", "completed" ] then "imported #{event.particulars["created"]} new and #{event.particulars["updated"]} updated products"
    in [ "Account", "plan_changed" ] then "changed the HardPoint plan from #{plan_name(event.particulars["from"])} to #{plan_name(event.particulars["to"])}#{by_platform(event)}"
    in [ "Account", "add_ons_changed" ] then "changed the HardPoint add-ons to #{pluralize(event.particulars["extra_branches"], "extra branch")} and #{pluralize(event.particulars["extra_registers"], "extra till")}, billed #{event.particulars["billing_interval"]}#{by_platform(event)}"
    in [ "Account", "invoice_issued" ] then "issued HardPoint invoice #{event.particulars["invoice"]} for #{money(event.particulars["amount"])}#{" (#{event.particulars["description"]})" if event.particulars["description"]}#{by_platform(event)}"
    in [ "Account", "subscription_paid" ] then "paid HardPoint invoice #{event.particulars["invoice"]} by #{event.particulars["provider"] == "mpesa" ? "M-Pesa" : event.particulars["provider"]} (#{event.particulars["receipt"]})"
    in [ "Account", "made_read_only" ] then "made the shop read-only: invoice #{event.particulars["invoice"]} is overdue"
    in [ "Account", "trial_extended" ] then "extended the free trial by #{pluralize(event.particulars["days"], "day")}#{by_platform(event)}"
    in [ "Account", "suspended" ] then "suspended the shop#{": #{event.particulars["reason"]}" if event.particulars["reason"]}#{by_platform(event)}"
    in [ "Account", "restored" ] then "restored the shop#{by_platform(event)}"
    in [ "Account", "closure_requested" ] then "asked to close the shop; its data will be deleted on #{Date.parse(event.particulars["deletion_on"]).to_fs(:long)}"
    in [ "Account", "closure_cancelled" ] then "cancelled closing the shop"
    in [ "Account", "export_requested" ] then "asked for an export of all the shop's data"
    in [ "Account", "backup_requested" ] then "made a backup of the shop"
    in [ "Account", "backup_downloaded" ] then "downloaded the backup taken #{backup_time(event)}"
    in [ "Account", "backup_deleted" ] then "deleted the backup taken #{backup_time(event)}"
    in [ "Account", "backup_failed" ] then "couldn't finish the shop's #{event.particulars["kind"] == "manual" ? "" : "automatic "}backup; the owners were emailed"
    in [ "Account", "quickbooks_exported" ] then "downloaded the QuickBooks export for #{event.particulars["month"]}"
    in [ "Account", "prices_changed" ] then "changed #{pluralize(event.particulars["count"], "product price")} (#{event.particulars["scope"]}, #{event.particulars["change"]})"
    in [ "ApiKey", "created" ] then "made the API key “#{subject}” (#{event.particulars["scope"] == "write" ? "read and write" : "read only"})"
    in [ "ApiKey", "revoked" ] then "revoked the API key “#{subject}”"
    in [ "WebhookEndpoint", "created" ] then "added a webhook to #{event.particulars["url"]}"
    in [ "WebhookEndpoint", "secret_rolled" ] then "made a new signing secret for the webhook to #{subject}"
    in [ "WebhookEndpoint", "disabled" ] then "switched off the webhook to #{event.particulars["url"]} after repeated failures"
    in [ "DocumentShare", "shared" ] then "sent #{subject.downcase} by WhatsApp"
    in [ "DocumentShare", "share_revoked" ] then "took back the WhatsApp link to #{subject.downcase}"
    in [ "User", "two_factor_enabled" ] then "turned on two-factor sign-in"
    in [ "User", "two_factor_disabled" ] then "turned off two-factor sign-in"
    in [ "User", "password_changed" ] then "changed their password"
    in [ _, "created" ] then "added #{thing} #{subject}"
    in [ _, "updated" ] then "changed #{thing} #{subject}: #{describe_changes(event)}"
    in [ _, "destroyed" ] then "removed #{thing} #{subject}"
    else "#{event.action.humanize(capitalize: false)} #{thing} #{subject}"
    end
  end

  def event_actor(event)
    event.creator&.name || (event.particulars["api_key"] ? "API key “#{event.particulars["api_key"]}”" : "HardPoint")
  end

  private
    def plan_name(key)
      Plan.find(key).name
    rescue ArgumentError
      key
    end

    def backup_time(event)
      Time.zone.parse(event.particulars["taken_at"].to_s)&.to_fs(:short) || "earlier"
    end

    def by_platform(event)
      " (HardPoint support: #{event.particulars["administrator"]})" if event.particulars["administrator"]
    end

    def variance_words(cents)
      cents = cents.to_i
      cents.zero? ? "balanced" : "#{money(cents.abs)} #{cents.negative? ? "short" : "over"}"
    end

    def whose(event)
      event.creator&.name == event.particulars["name"] ? "their" : "#{event.particulars["name"]}'s"
    end

    def describe_changes(event)
      (event.particulars["changes"] || {}).map do |attribute, (from, to)|
        "#{attribute.humanize(capitalize: false)} from “#{from.presence || "blank"}” to “#{to.presence || "blank"}”"
      end.to_sentence
    end
end
