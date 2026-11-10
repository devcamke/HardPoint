# One part of a job (a wall, a slab…). Subclasses list their fields, which the form draws, and work out the
# materials. A part with its main measurements left empty is skipped.
class MaterialCalculator::Part
  Field = Data.define(:name, :label, :options, :default, :hint) do
    def initialize(name:, label:, options: nil, default: nil, hint: nil) = super
    def select? = options.present?
  end

  class_attribute :title, :description, :fields, :required, :assumptions

  attr_reader :values

  def initialize(values = {})
    values = values.to_h.stringify_keys
    @values = fields.to_h { |field| [ field.name, values[field.name].presence || field.default&.to_s ] }
  end

  def kind = self.class.name.demodulize.underscore

  def filled? = required.all? { number(_1) }

  # { material key => quantity in its unit }, before rounding.
  def materials
    filled? ? calculate.select { |_, quantity| quantity.to_d.positive? } : {}
  end

  # What was measured, for the quote and the page: "Wall, 12 × 3 m".
  def summary = title

  private
    def number(name) = MaterialCalculator.number(values[name])

    def choice(name)
      field = fields.find { _1.name == name }
      values[name].presence_in(field.options.map(&:last).map(&:to_s)) || field.default.to_s
    end

    def measure(value) = value.to_d.round(2).to_s("F").delete_suffix(".0")
end
