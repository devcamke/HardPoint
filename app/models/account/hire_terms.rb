# The terms printed on a tool-hire agreement for the customer to sign. A shop can write its own, one term per
# line; until it does, the standard terms apply. Each agreement keeps a copy of the terms it was made under.
module Account::HireTerms
  extend ActiveSupport::Concern

  STANDARD = [
    "The tools remain the property of the shop. They are hired for use at the site given and may not be lent or hired to anyone else.",
    "Charges run from the time the tools go out until they are returned, by the day (24 hours, with one hour's grace), or by the week where a weekly rate is shown.",
    "The hirer returns the tools clean and in the condition they were received, and pays for repairs or replacement if they are damaged, lost or stolen.",
    "The deposit is set against the charges when the tools come back; any balance is paid or refunded then.",
    "Tools kept past the return time continue to be charged. The shop may collect tools not returned within 3 days of the return time."
  ].freeze
  MAX_TERMS = 20
  MAX_TERM_LENGTH = 600

  # "1. Tools stay ours" and "- Tools stay ours" become "Tools stay ours": the PDF numbers them itself.
  def self.split(text)
    text.to_s.lines.map { _1.strip.sub(/\A(?:\d+[.)]|[-*•])\s*/, "").squish }.compact_blank
  end

  included do
    # Saving the standard terms unchanged keeps the shop on the standard terms.
    normalizes :hire_terms, with: ->(text) { (terms = Account::HireTerms.split(text)) == STANDARD ? nil : terms.join("\n").presence }

    validate :hire_terms_fit_on_the_agreement, if: :hire_terms_changed?
  end

  def hire_terms_list
    hire_terms.present? ? Account::HireTerms.split(hire_terms) : STANDARD
  end

  def own_hire_terms?
    hire_terms.present?
  end

  private
    def hire_terms_fit_on_the_agreement
      terms = Account::HireTerms.split(hire_terms)
      errors.add :hire_terms, "can have at most #{MAX_TERMS} terms" if terms.size > MAX_TERMS
      if (long = terms.index { _1.length > MAX_TERM_LENGTH })
        errors.add :hire_terms, "term #{long + 1} is too long (at most #{MAX_TERM_LENGTH} characters)"
      end
    end
end
