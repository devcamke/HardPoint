module EventsHelper
  def event_summary(event)
    subject = event.particulars["name"]
    thing = event.eventable_type.constantize.model_name.human.downcase

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
    in [ "Sale", "voided" ] then "voided sale #{subject} (#{money(event.particulars["total"])}), approved by #{event.particulars["approver"]}: #{event.particulars["reason"]}"
    in [ "Sale", "returned" ] then "took back items from #{subject}: #{event.particulars["return_number"]}, refunded #{money(event.particulars["total"])} by #{event.particulars["refund_method"].to_s.humanize.downcase}"
    in [ "Sale", "discount_approved" ] then "got a #{event.particulars["percent"]}% discount approved by #{event.particulars["approver"]}"
    in [ "Membership", "approval_pin_set" ] then "set their approval PIN"
    in [ "User", "two_factor_enabled" ] then "turned on two-factor sign-in"
    in [ "User", "two_factor_disabled" ] then "turned off two-factor sign-in"
    in [ _, "created" ] then "added #{thing} #{subject}"
    in [ _, "updated" ] then "changed #{thing} #{subject}: #{describe_changes(event)}"
    in [ _, "destroyed" ] then "removed #{thing} #{subject}"
    else "#{event.action.humanize(capitalize: false)} #{thing} #{subject}"
    end
  end

  def event_actor(event)
    event.creator&.name || "HardPoint"
  end

  private
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
