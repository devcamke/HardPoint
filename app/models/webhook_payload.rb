# The "data" of a webhook: the same JSON the API returns for that record.
module WebhookPayload
  PARTIALS = {
    "Sale" => [ "api/v1/sales/sale", :sale ], "Product" => [ "api/v1/products/product", :product ],
    "StockLevel" => [ "api/v1/stock_levels/stock_level", :stock_level ], "CustomerOrder" => [ "api/v1/orders/order", :order ],
    "Customer" => [ "api/v1/customers/customer", :customer ]
  }.freeze

  def self.for(record)
    partial, local = PARTIALS.fetch(record.class.name)
    Time.use_zone("UTC") do # like the API's answers
      JSON.parse(Api::V1::BaseController.render(partial: partial, locals: { local => record }, formats: [ :json ]))
    end
  end
end
