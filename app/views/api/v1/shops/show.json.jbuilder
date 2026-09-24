json.extract! @account, :name, :subdomain, :currency, :time_zone, :plan
json.branches @branches, partial: "api/v1/branches/branch", as: :branch
