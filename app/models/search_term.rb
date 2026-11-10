# A word of a product's name or SKU, or of a customer's name or phone number, kept by database triggers (see the
# migration that creates the table). Search finds records by the start of their words here, because comparing text
# can use an index under row-level security where ILIKE can't.
class SearchTerm < ApplicationRecord
  include AccountOwned

  # Beyond any character a word can contain, so [word, word + LAST) is every term starting with the word.
  LAST = "\u{10FFFF}"

  # Ids of the records of a table with a term starting with the word, as a subquery. Named shop by shop so the
  # index is used; with isolation lifted (no shop) it's every shop's.
  def self.starting_with(table, word)
    word = word.to_s.downcase.first(100)
    terms = where(record_type: table).where("search_terms.term >= ? AND search_terms.term < ?", word, word + LAST)
    terms = terms.where(account_id: Current.account.id) if Current.account
    terms.select(:record_id)
  end

  # Ids of the records with a term starting with every word, as one Arel set ("cem 50" is cem's ∩ 50's).
  def self.with_every_word(table, words)
    words.map { |word| starting_with(table, word).arel }.reduce { |all, next_word| Arel::Nodes::Intersect.new(all, next_word) }
  end
end
