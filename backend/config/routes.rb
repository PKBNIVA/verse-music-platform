Rails.application.routes.draw do
  scope :api do
    get "health", to: "health#show"
    get "live", to: "health#show"
    get "readiness", to: "health#readiness"
    post "auth/register", to: "auth#register"
    post "auth/login", to: "auth#login"
    post "auth/logout", to: "auth#logout"
    post "auth/request-email-verification", to: "auth#request_verification"
    post "auth/verify-email", to: "auth#verify_email"
    post "auth/forgot-password", to: "auth#forgot_password"
    post "auth/reset-password", to: "auth#reset_password"
    post "auth/otp/request", to: "auth#otp_request"
    post "auth/otp/verify", to: "auth#otp_verify"
    get "me", to: "auth#me"
    put "profile", to: "profiles#update"

    resources :jobs, only: %i[index show create] do
      member { post :apply }
    end
    get "saved-jobs", to: "jobs#saved"
    post "saved-jobs/:id", to: "jobs#save"
    delete "saved-jobs/:id", to: "jobs#unsave"
    resources :applications, only: %i[index destroy]
    resources :job_alerts, path: "job-alerts", only: %i[index create update destroy]

    namespace :employer do
      resources :jobs, only: :update
      resources :applications, only: %i[index update]
    end
    namespace :admin do
      get :health, to: "health#show"
      get :stats, to: "stats#index"
      get :tester, to: "tester#index"
      resources :users, only: %i[index update] do
        member { post :grant_plan, path: "grant-plan" }
      end
      resources :jobs, only: %i[index update]
      resources :reviews, only: %i[index update]
      resources :verifications, only: %i[index update]
      resources :reports, only: %i[index update]
      get :audit, to: "operations#audit"
      get :subscriptions, to: "operations#subscriptions"
      get "billing-attempts", to: "operations#billing_attempts"
      post "billing-attempts/:id/reconcile", to: "operations#reconcile_billing_attempt"
      resources :billing_events, path: "billing-events", only: %i[index show]
      get :bookings, to: "operations#bookings"
      post "search/reindex", to: "search#reindex"
      get "demo-data", to: "demo_data#index"
      post "demo-data", to: "demo_data#create"
      delete "demo-data", to: "demo_data#destroy_all"
      get "demo-data/jobs/:id", to: "demo_data#job_status"
      delete "demo-data/:batch", to: "demo_data#destroy"
    end

    resources :portfolio, only: %i[index create update destroy], controller: "portfolio"
    get "notifications/unread", to: "notifications#unread"
    post "notifications/read-all", to: "notifications#read_all"
    get "notifications/preferences", to: "notifications#preferences"
    patch "notifications/preferences", to: "notifications#update_preferences"
    get "notifications/unsubscribe", to: "notifications#unsubscribe"
    post "notifications/unsubscribe", to: "notifications#unsubscribe"
    resources :notifications, only: %i[index update]
    resources :reports, only: :create
    resources :verification_requests, path: "verification-requests", only: :create
    resources :reviews, only: %i[index create]
    resources :resources, only: :index
    get "taxonomy", to: "catalog#taxonomy"
    get "dashboard", to: "dashboard#show"
    get "search", to: "search#index"
    get "search/status", to: "search#status"
    post "uploads/presign", to: "uploads#presign"
    put "uploads/local", to: "uploads#local"
    post "uploads/:id/complete", to: "uploads#complete", as: :complete_upload
    delete "uploads/:id", to: "uploads#destroy", as: :upload
    get "public/talent", to: "talent#public_index"
    get "public/talent/:id", to: "talent#public_show"
    get "candidates", to: "talent#index"
    get "candidates/compare/list", to: "talent#compare"
    get "candidates/:id", to: "talent#show"
    post "shortlists/:id", to: "talent#shortlist"
    delete "shortlists/:id", to: "talent#unshortlist"
    get "recent-activity", to: "talent#recent"
    delete "recent-activity", to: "talent#clear_recent"
    get "employers", to: "talent#employers"
    resources :availability, only: %i[index create destroy], controller: "availability"
    resources :conversations, only: %i[index create] do
      resources :messages, only: %i[index create], controller: "messages"
    end
    get "public/acts", to: "acts#public_index"
    get "public/acts/:id", to: "acts#public_show"
    get "acts/me", to: "acts#mine"
    resources :acts, only: %i[index show create update destroy] do
      member do
        post :members, to: "acts#add_member"
        delete "members/:member_id", to: "acts#remove_member"
      end
    end
    resources :bookings, only: %i[index create] do
      member do
        post :quote
        post :status, to: "bookings#change_status"
        post "payment-order", action: :payment_order
        get :payments
      end
    end
    post "booking-payments/:id/confirm", to: "bookings#confirm_payment"
    resources :organizations, only: %i[index create] do
      member do
        get :members, to: "organizations#members"
        post :members, to: "organizations#add_member"
        delete "members/:userId", to: "organizations#remove_member"
      end
    end
    resources :urgent_requests, path: "urgent-requests", only: %i[index create update] do
      member do
        post :respond
        get :responses
      end
    end
    resources :talent_folders, path: "talent-folders", only: %i[index show create destroy] do
      member { post "candidates/:candidateId", to: "talent_folders#add_candidate" }
    end
    resources :band_projects, path: "band-projects", only: %i[index create] do
      member do
        post :roles, to: "band_projects#add_role"
        post "roles/:roleId/publish", to: "band_projects#publish_role"
      end
    end
    resources :crew_plans, path: "crew-plans", only: %i[index create] do
      member { post :convert }
    end
    namespace :billing do
      get :plans, to: "billing#plans"
      get :subscription, to: "billing#subscription"
      post :checkout, to: "billing#checkout"
      post :cancel, to: "billing#cancel"
      post "webhook/razorpay", to: "billing#razorpay_webhook"
    end
    # Local Razorpay simulator (RAZORPAY_SIMULATOR=true, test key, never production).
    constraints(->(_request) { RazorpaySimulator.enabled? }) do
      scope "dev/razorpay", controller: "dev/razorpay_simulator", as: "razorpay_simulator" do
        post :checkout
        post "subscriptions/:id/:simulate", action: :subscription_lifecycle
        post "payments/:id/refund", action: :refund
        post :webhooks, action: :webhook
      end
    end
  end
end
