json.extract! job, :id, :customer_id, :name, :reference, :site, :status, :budget_cents
json.spent_cents @spent[job.id]
json.extract! job, :closed_at, :created_at, :updated_at
