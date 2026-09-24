Rails.application.routes.draw do
  # The bare domain (hardpoint.app) hosts signup; each shop lives on its own subdomain (acme.hardpoint.app).
  constraints ->(request) { request.subdomain.blank? } do
    resource :signup, only: %i[ new create ]
    root "signups#new", as: :signup_root
  end

  constraints ->(request) { request.subdomain.present? } do
    resource :session
    resources :passwords, param: :token
    resource :account, only: %i[ edit update ]
    resources :branches, except: :show
    resources :memberships, except: :show
    root "dashboards#show"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
