Rails.application.routes.draw do
  # Subscription payments to HardPoint itself: Safaricom's answer to a prompt (found by the
  # platform's secret token) and Paystack's signed webhooks.
  post "webhooks/billing/mpesa/:token", to: "webhooks/billing_mpesa#create", as: :billing_mpesa_webhook
  post "webhooks/paystack", to: "webhooks/paystack#create", as: :paystack_webhook

  # Callbacks from Safaricom, on any host. The shop is found by the secret token in the path.
  scope "webhooks/mpesa/:token", controller: "webhooks/mpesa", as: :mpesa_webhook do
    post "stk", action: :stk, as: :stk
    post "c2b/confirmation", action: :confirmation, as: :confirmation
    post "c2b/validation", action: :validation, as: :validation
  end

  # The bare domain (hardpoint.app) hosts the public site, help and signup; each shop lives on its own
  # subdomain (acme.hardpoint.app).
  constraints ->(request) { request.subdomain.blank? } do
    resource :signup, only: %i[ new create ]
    resource :shop_lookup, only: %i[ new create ]
    get "pricing", to: "pages#pricing"
    get "privacy", to: "pages#privacy"
    get "developers", to: "pages#developers", as: :developer_docs
    get "help", to: "help#index", as: :help
    get "help/:id", to: "help#show", as: :help_article
    root "pages#home", as: :marketing_root
  end

  # The public API on api.<domain>; the API key says which shop (docs at /developers on the bare domain).
  constraints subdomain: "api" do
    scope module: "api/v1", path: "v1", as: "api_v1", defaults: { format: :json } do
      resource :shop, only: :show
      resources :branches, only: :index
      resources :products, only: %i[ index show create update ]
      resources :stock_levels, only: :index
      resources :customers, only: %i[ index show create update ]
      resources :jobs, only: %i[ index show ]
      resources :sales, only: %i[ index show ]
      resources :orders, only: %i[ index show create ] do
        resource :cancellation, only: :create, module: :orders
      end
    end
  end

  # Platform administration on admin.<domain>.
  constraints subdomain: "admin" do
    namespace :admin, path: "" do
      resource :session, only: %i[ new create destroy ]
      resource :two_factor, only: %i[ new create ]
      resources :accounts, only: %i[ index show ] do
        scope module: :accounts do
          resource :plan, only: :update
          resource :trial_extension, only: :create
          resource :suspension, only: %i[ create destroy ]
          resources :payments, only: :create
        end
      end
      resources :impersonations, only: :create
      resources :announcements, except: :show
      resources :support_requests, only: %i[ index update ]
      resource :database, only: :show
      root "accounts#index"
    end
  end

  constraints ->(request) { request.subdomain.present? && !request.subdomain.in?(%w[ admin api ]) } do
    resource :session do
      scope module: :sessions do
        resource :two_factor, only: %i[ new create ]
        resource :switch, only: %i[ new create ]
        resource :impersonation, only: %i[ new create ]
      end
    end
    namespace :my do
      resource :profile, only: :show
      resource :two_factor, only: %i[ new create destroy ]
      resource :recovery_codes, only: :show
      resource :approval_pin, only: %i[ edit update ]
      resource :pin, only: %i[ edit update destroy ]
      resource :daily_summary, only: :update
    end
    resources :passwords, param: :token
    resource :account, only: %i[ edit update ]
    resources :branches, except: :show
    resources :registers, except: :show
    resources :memberships, except: :show
    resources :events, only: :index
    resource :settings, only: :show
    resources :support_requests, only: %i[ new create ]
    resource :account_data, only: :show
    resource :developers, only: :show
    resource :storefront, only: %i[ edit update ]

    # Tool hire (the tools first, so /hire/tools isn't taken for an agreement).
    resources :hire_items, path: "hire/tools", except: :show
    resources :hire_agreements, path: "hire", only: %i[ index new create show ] do
      scope module: :hire_agreements do
        resource :return, only: %i[ new create ]
        resource :extension, only: :create
        resource :cancellation, only: :create
        resource :reminder, only: :create
        resource :document, only: :show
      end
    end

    # The shop's public online store.
    namespace :store do
      root "products#index"
      resources :products, only: %i[ index show ]
      resource :cart, only: :show
      resources :cart_items, only: %i[ create update destroy ], param: :product_id
      resource :checkout, only: %i[ new create ]
      resources :orders, only: :show, param: :token
    end
    resources :api_keys, only: %i[ new create destroy ]
    resources :webhook_endpoints, except: :index do
      scope module: :webhook_endpoints do
        resource :test, only: :create
        resource :secret, only: :create
        resource :enablement, only: :create
        resources :deliveries, only: [] do
          resource :redelivery, only: :create
        end
      end
    end
    resources :account_exports, only: %i[ create show ]
    resource :account_closure, only: %i[ create destroy ]
    resource :onboarding, only: :show do
      scope module: :onboardings do
        resource :tax_confirmation, only: :create
        resource :test_receipt, only: %i[ show create ]
        resource :completion, only: :create
      end
    end

    resources :categories, :brands, :units, :tax_rates, :price_lists, except: :show

    resources :products do
      scope module: :products do
        resources :units, only: %i[ create destroy ]
        resources :barcodes, only: %i[ create destroy ]
        resources :prices, only: %i[ create destroy ]
        resources :components, only: %i[ create destroy ]
        resources :movements, only: :index
      end
    end
    resources :product_imports, only: %i[ index new create show ] do
      resource :run, only: :create, module: :product_imports
    end
    resource :labels, only: %i[ new show ]

    resource :stock, only: :show, controller: :stock
    resources :stock_adjustments, only: %i[ new create ]
    resources :stock_movements, only: :index
    resources :stock_batches, path: "batches", only: %i[ index show ] do
      resource :write_off, only: :create, module: :stock_batches
    end
    resources :stock_transfers, only: %i[ index new create show ] do
      scope module: :stock_transfers do
        resource :receipt, only: :create
        resource :cancellation, only: :create
      end
    end
    resources :stock_counts, only: %i[ index new create show ] do
      scope module: :stock_counts do
        resources :lines, only: :update
        resource :scan, only: :create
        resource :submission, only: :create
        resource :approval, only: :create
        resource :cancellation, only: :create
      end
    end
    resource :reorder_list, only: :show

    # The till
    resource :pos, only: :show, controller: :pos
    namespace :pos do
      resource :till, only: %i[ new create ]
      resources :products, only: :index
      resources :customers, only: :index
      resource :customer, only: :update
      resource :job, only: :update
      resources :lines, only: %i[ create update destroy ]
      resource :discount, only: :update
      resources :payments, only: %i[ create destroy ]
      resource :parking, only: :create
      resources :parked_sales, only: :index
      resource :discard, only: :create
      resources :mpesa_requests, only: %i[ create show destroy ]
      resources :mpesa_matches, only: :create
      resource :catalogue, only: :show
      resources :offline_sales, only: %i[ new create ]
      resource :offline, only: :show
      resource :display, only: :show
      resources :drawer_openings, only: :create
    end

    resources :shifts, only: %i[ index show new create ] do
      scope module: :shifts do
        resources :cash_movements, only: %i[ new create ]
        resource :closing, only: %i[ new create ]
      end
    end
    resources :sales, only: %i[ index show ] do
      scope module: :sales do
        resource :receipt, only: :show
        resource :receipt_email, only: :create
        resource :recall, only: :create
        resource :void, only: %i[ new create ]
        resources :returns, only: %i[ new create ]
        resource :invoice, only: :show
        resource :receipt_text, only: :create
      end
    end
    resources :returns, only: %i[ index show ], controller: :sale_returns

    # Customers, orders and accounts
    resources :customers, except: :destroy do
      scope module: :customers do
        resources :payments, only: %i[ new create ]
        resource :statement, only: :show
        resource :statement_email, only: :create
        resource :balance_reminder, only: :create
      end
    end
    # The stock app for phones.
    namespace :mobile, path: "m" do
      root "products#index"
      resources :products, only: %i[ index show ]
      resources :stock_counts, path: "counts", only: %i[ index show ] do
        resources :count_lines, path: "lines", only: :index
        resources :count_entries, path: "entries", only: :create
      end
      resources :purchase_orders, path: "receive", only: %i[ index show ] do
        resources :receipt_lines, path: "lines", only: :index
        resources :receipt_entries, path: "entries", only: :create
        resource :goods_receipt, only: :create
      end
    end

    resources :currencies, only: %i[ index create update destroy ]
    resources :jobs, except: :destroy do
      scope module: :jobs do
        resource :closure, only: %i[ create destroy ]
        resource :summary, only: :show
      end
    end
    resources :customer_orders, path: "orders", except: :destroy do
      scope module: :customer_orders do
        resource :confirmation, only: :create
        resource :readiness, only: :create
        resource :cancellation, only: :create
        resource :email, only: :create
        resource :collection, only: :create
        resources :deposits, only: %i[ new create ]
      end
    end
    resource :receivables, only: :show

    # The shop's HardPoint subscription
    resource :billing, only: :show do
      scope module: :billings do
        resource :plan, only: :update
        resource :subscription_start, only: :create
        resources :mpesa_payments, only: %i[ create show ]
        resources :card_payments, only: :create
        resource :card_return, only: :show
        resource :card_simulator, only: %i[ show create ]
        resources :invoices, only: :show
      end
    end

    # Integrations
    resources :mpesa_shortcodes, path: "mpesa", except: %i[ show destroy ] do
      scope module: :mpesa_shortcodes do
        resource :connection_test, only: :create
        resource :c2b_registration, only: :create
      end
    end

    resources :etims_devices, path: "etims", except: %i[ show destroy ] do
      scope module: :etims_devices do
        resource :initialization, only: :create
      end
    end
    resources :etims_submissions, path: "etims/submissions", only: %i[ index show ] do
      scope module: :etims_submissions do
        resource :retry, only: :create
      end
    end
    resource :etims_retries, path: "etims/retries", only: :create
    resources :sms_messages, path: "texts", only: :index

    # Direct printing through QZ Tray: its certificate, and signatures for its requests.
    resource :qz_certificate, only: :show
    resource :qz_signature, only: :create

    # Reports
    resources :reports, only: %i[ index show ], param: :key
    resources :delivery_notes, path: "deliveries", only: %i[ index show new create ] do
      scope module: :delivery_notes do
        resource :dispatch, only: :create
        resource :delivery, only: :create
        resource :cancellation, only: :create
      end
    end

    # Purchasing
    resources :suppliers, except: :destroy do
      scope module: :suppliers do
        resources :products, only: %i[ create update destroy ]
        resources :payments, only: %i[ new create ]
      end
    end
    resources :purchase_orders, except: :destroy do
      scope module: :purchase_orders do
        resource :sending, only: :create
        resource :cancellation, only: :create
      end
    end
    resources :goods_receipts, only: %i[ index new create show ]
    resource :reorder_suggestions, only: :show
    resources :supplier_invoices, only: %i[ index new create show ]
    resource :payables, only: :show
    root "dashboards#show"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The installable till (web app manifest) and its service worker, which must sit at the root to cover every page.
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "stock-manifest" => "pwa#stock_manifest", as: :pwa_stock_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
end
