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
      resource :pin, only: %i[ edit update destroy ]
    end
    resources :passwords, param: :token
    resource :account, only: %i[ edit update ]
    resources :branches, except: :show
    resources :registers, except: :show
    resources :memberships, except: :show
    resources :events, only: :index
    root "dashboards#show"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
