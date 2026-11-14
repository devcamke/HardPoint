Rails.application.routes.draw do
  # In development shops live on *.localhost. An IP address can't carry a subdomain, so a visit to 127.0.0.1 (the address
  # the server prints when it starts) would lose the shop on every redirect into it: send it to localhost instead.
  if Rails.env.development?
    constraints host: /\A(127\.0\.0\.1|\[?::1\]?)\z/ do
      get "(*path)", format: false, to: redirect(status: 302) { |_params, request| "#{request.protocol}localhost:#{request.port}#{request.fullpath}" }
    end
  end

  # Files are only uploaded through the app's own forms. Active Storage's direct uploads would let anyone, signed in
  # or not, put files on the server, so that route answers Not Found (it's drawn after these, so this one wins).
  post "rails/active_storage/direct_uploads", to: proc { [ 404, { "content-type" => "text/plain" }, [ "Not found" ] ] }

  # Subscription payments to HardPoint itself: Safaricom's answer to a prompt (found by the
  # platform's secret token) and Paystack's signed webhooks.
  post "webhooks/billing/mpesa/:token", to: "webhooks/billing_mpesa#create", as: :billing_mpesa_webhook
  post "webhooks/paystack", to: "webhooks/paystack#create", as: :paystack_webhook

  # Meta's status updates for HardPoint's WhatsApp number (signature-checked), on any host; GET is Meta's address check.
  get "webhooks/whatsapp", to: "webhooks/whatsapp#show", as: :whatsapp_webhook
  post "webhooks/whatsapp", to: "webhooks/whatsapp#create"

  # Bounces and complaints from AWS SES, through its SNS topic (signature-checked), on any host.
  post "webhooks/ses", to: "webhooks/ses#create", as: :ses_webhook

  # Callbacks from Airtel, on any host; the shop is found by the secret token in the path.
  post "webhooks/airtel/:token", to: "webhooks/airtel#create", as: :airtel_webhook

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
    get "terms", to: "pages#terms"
    get "data-processing", to: "pages#data_processing", as: :data_processing
    get "sla", to: "pages#sla"
    get "developers", to: "pages#developers", as: :developer_docs
    get "help", to: "help#index", as: :help
    get "help/:id", to: "help#show", as: :help_article
    get "llms.txt", to: "seo#llms", as: :llms, format: false
    # Pages about one job (KRA eTIMS, M-Pesa, offline) or one market, at /kra-etims-pos and the like.
    get ":id", to: "solutions#show", as: :solution, constraints: { id: Regexp.union(SolutionPage.slugs) }
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
          resource :add_ons, only: :update
          resource :trial_extension, only: :create
          resources :invoices, only: :create
          resource :suspension, only: %i[ create destroy ]
          resources :payments, only: :create
          resources :two_factor_resets, only: :create
        end
      end
      resources :impersonations, only: :create
      resources :events, only: :index
      resources :announcements, except: :show
      resources :support_requests, only: %i[ index update ]
      resource :database, only: :show
      resource :email, only: :show
      resources :email_suppressions, only: :destroy
      resource :adoption, only: :show
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
      resources :devices, only: %i[ index destroy ] # the sessions you're signed in with
      resource :password, only: %i[ edit update ]
      resource :two_factor, only: %i[ new create destroy ]
      resource :recovery_codes, only: :show
      resource :approval_pin, only: %i[ edit update ]
      resource :pin, only: %i[ edit update destroy ]
      resource :emails, only: :update
    end
    resources :passwords, param: :token
    get "email_confirmations/:token", to: "email_confirmations#show", as: :email_confirmation
    resource :account, only: %i[ edit update ]
    resources :branches, except: :show
    resources :registers, except: :show
    resources :memberships, except: :show do
      resource :two_factor_reset, only: :create, module: :memberships
    end
    resources :events, only: :index
    resource :settings, only: :show
    resource :features, only: %i[ show update ]
    resource :search, only: :show
    resources :price_changes, only: %i[ new create ]
    resource :quickbooks_export, path: "reports/quickbooks", only: %i[ show update ]
    # Documents sent by WhatsApp, opened without signing in (DocumentShare).
    get "share/:token", to: "shares#show", as: :share
    # A customer's own page (PortalLink), opened without signing in, and paying from it with M-Pesa.
    scope "portal/:token", as: :portal do
      get "/", to: "portals#show", as: ""
      get "statement", to: "portals#statement", as: :statement
      get "invoices/:id", to: "portals#invoice", as: :invoice
      get "quotes/:id", to: "portals#quote", as: :quote
      resources :payments, only: %i[ create show ], controller: "portal_payments"
    end
    resources :whatsapp_messages, only: %i[ index create ]
    resources :shares, only: %i[ create destroy ], as: :document_shares # links made by the WhatsApp buttons, and taking one back
    resources :support_requests, only: %i[ new create ]
    resource :account_data, only: :show
    resource :developers, only: :show
    resource :storefront, only: %i[ edit update ]

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
    resources :account_backups, only: %i[ create show destroy ]
    resource :backup_schedule, only: :update
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
        resource :reorder_level, only: :update
        resources :offcuts, only: %i[ create destroy ]
      end
    end
    resources :product_imports, only: %i[ index new create show ] do
      resource :run, only: :create, module: :product_imports
    end
    resource :labels, only: %i[ new show ]
    resource :label_queue, path: "labels/queue", only: %i[ show update ]

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
        resources :lines, only: :update do
          resources :batch_counts, only: :create
        end
        resource :scan, only: :create
        resource :submission, only: :create
        resource :approval, only: :create
        resource :cancellation, only: :create
      end
    end
    resource :reorder_list, only: :show
    resource :suggested_reorder_levels, only: :create

    # The till
    resource :pos, only: :show, controller: :pos
    namespace :pos do
      resource :till, only: %i[ new create ]
      resources :products, only: :index
      resources :customers, only: :index
      resource :customer, only: :update
      resources :fundis, only: :index
      resource :fundi, only: :update
      resource :job, only: :update
      resources :lines, only: %i[ create update destroy ]
      resource :discount, only: :update
      resources :payments, only: %i[ create destroy ]
      resource :completion, only: :create
      resource :parking, only: :create
      resource :transport, only: :create
      resources :parked_sales, only: :index
      resource :discard, only: :create
      resources :mpesa_requests, only: %i[ create show destroy ]
      resources :airtel_requests, only: %i[ create show destroy ]
      resources :airtel_matches, only: :create
      resources :mpesa_matches, only: :create
      resource :catalogue, only: :show
      resources :offline_sales, only: %i[ new create ]
      resource :offline, only: :show
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
    resource :customer_import, only: %i[ new create ]
    resources :customers, except: :destroy do
      scope module: :customers do
        resources :payments, only: %i[ new create ]
        resources :write_offs, only: %i[ new create ]
        resource :statement, only: :show
        resource :statement_email, only: :create
        resource :balance_reminder, only: :create
        resource :portal_link, only: %i[ create destroy ]
        resource :credit_hold_lift, only: %i[ create destroy ]
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

    resources :currencies, only: %i[ index create update destroy ] do
      resource :market_rate, only: :create, module: :currencies
    end
    resources :promotions
    # Making HardPoint the shop's own: its colours and logo, and the choices that tune how it works.
    resource :appearance, only: %i[ edit update ]
    resource :preferences, only: %i[ edit update ]
    # The material calculator: a job's parts into materials, then a quote; and which product is each material.
    resource :material_estimate, only: %i[ new create ]
    resource :material_products, only: %i[ edit update ]
    # Fundis who bring customers, their commission rates, and paying them.
    resource :fundi_rates, only: %i[ edit update ]
    resources :fundis, except: :destroy do
      resources :payouts, only: %i[ new create ], module: :fundis
    end
    resources :jobs, except: :destroy do
      scope module: :jobs do
        resource :closure, only: %i[ create destroy ]
        resource :summary, only: :show
        resource :client_bill, only: :show
      end
    end
    resources :customer_orders, path: "orders", except: :destroy do
      scope module: :customer_orders do
        resource :confirmation, only: :create
        resource :readiness, only: :create
        resource :cancellation, only: :create
        resource :email, only: :create
        resource :collection, only: :create
        resource :forfeiture, only: :create
        resources :deposits, only: %i[ new create ]
      end
    end
    resource :receivables, only: :show

    # The shop's HardPoint subscription
    resource :billing, only: :show do
      scope module: :billings do
        resource :plan, only: :update
        resource :add_ons, only: :update
        resource :subscription_start, only: :create
        resources :mpesa_payments, only: %i[ create show ]
        resources :card_payments, only: :create
        resource :card_return, only: :show
        resource :card_simulator, only: %i[ show create ]
        resources :invoices, only: :show
      end
    end

    # Integrations
    resources :airtel_merchants, path: "airtel", except: %i[ show destroy ] do
      resource :connection_test, only: :create, module: :airtel_merchants
    end
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
    # Invoices suppliers have issued to the shop, as KRA holds them (Etims::Purchase).
    resources :etims_purchases, path: "kra_invoices", only: %i[ index show ] do
      collection { resource :check, only: :create, module: :etims_purchases, as: :etims_purchases_check }
      scope module: :etims_purchases do
        resource :receipt, only: :create
        resource :invoice, only: :create
        resource :dismissal, only: %i[ create destroy ]
      end
    end
    resources :sms_messages, path: "texts", only: :index

    # Direct printing through QZ Tray: its certificate, and signatures for its requests.
    resource :qz_certificate, only: :show
    resource :qz_signature, only: :create

    # Reports
    resources :reports, only: %i[ index show ], param: :key

    # Guided tours of the screens (config/help_tours.yml)
    resources :tours, only: :index

    resources :delivery_notes, path: "deliveries", only: %i[ index show new create ] do
      scope module: :delivery_notes do
        resource :dispatch, only: :create
        resource :delivery, only: :create
        resource :cancellation, only: :create
      end
    end

    # Purchasing
    resource :supplier_import, only: %i[ new create ]
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
        resource :closure, only: :create
      end
    end
    resources :goods_receipts, only: %i[ index new create show ]
    resource :reorder_suggestions, only: :show
    resources :supplier_invoices, only: %i[ index new create show ]
    resources :supplier_returns, only: %i[ index new create show ] do
      scope module: :supplier_returns do
        resource :credit_note, only: :create
        resource :email, only: :create
      end
    end
    resource :payables, only: :show
    root "dashboards#show"
  end

  # Where to report a vulnerability (RFC 9116), on any host.
  get ".well-known/security.txt", to: "pages#security_txt", as: :security_txt

  # The platform's checks for the uptime monitor (PlatformHealth): 200 or 503, on any host.
  get "health", to: "health#show", as: :health

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # For search engines: what they may read on this host, and the public site's pages (bare domain only).
  get "robots.txt" => "seo#robots", as: :robots, format: false
  get "sitemap.xml" => "seo#sitemap", as: :sitemap, format: false

  # The installable till (web app manifest) and its service worker, which must sit at the root to cover every page.
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "stock-manifest" => "pwa#stock_manifest", as: :pwa_stock_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
end
