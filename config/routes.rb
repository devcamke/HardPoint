Rails.application.routes.draw do
  # The bare domain (hardpoint.app) hosts signup; each shop lives on its own subdomain (acme.hardpoint.app).
  constraints ->(request) { request.subdomain.blank? } do
    resource :signup, only: %i[ new create ]
    root "signups#new", as: :signup_root
  end

  # Platform administration on admin.<domain>.
  constraints subdomain: "admin" do
    namespace :admin, path: "" do
      resource :session, only: %i[ new create destroy ]
      resource :two_factor, only: %i[ new create ]
      resources :accounts, only: %i[ index show ]
      resources :impersonations, only: :create
      root "accounts#index"
    end
  end

  constraints ->(request) { request.subdomain.present? && request.subdomain != "admin" } do
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
    end
    resources :passwords, param: :token
    resource :account, only: %i[ edit update ]
    resources :branches, except: :show
    resources :registers, except: :show
    resources :memberships, except: :show
    resources :events, only: :index
    resource :settings, only: :show

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
      resources :lines, only: %i[ create update destroy ]
      resource :discount, only: :update
      resources :payments, only: %i[ create destroy ]
      resource :parking, only: :create
      resources :parked_sales, only: :index
      resource :discard, only: :create
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
      end
    end
    resources :returns, only: %i[ index show ], controller: :sale_returns
    resources :customers, except: :destroy
    root "dashboards#show"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
