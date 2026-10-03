Rails.application.routes.draw do
  # Full-page browser redirects (the Google consent screen and its callback), not JSON, so
  # these are outside the /api scope. See GoogleAuthController.
  get "auth/google/start", to: "google_auth#start"
  get "auth/google/callback", to: "google_auth#callback"

  get "sitemap.xml", to: "sitemaps#show"
  get "sitemaps/:part.:format", to: "sitemaps#part", constraints: { part: /\d+/, format: /xml/ }
  get "share/opportunities/:id", to: "share_pages#job"
  get "share/professionals/:id", to: "share_pages#professional"
  get "share/acts/:id", to: "share_pages#act"
  get "share/p/:slug", to: "share_pages#portfolio"

  # Public "I'm verified on MusiLynk" story/landscape cards for Instagram/WhatsApp sharing
  # (ShareCardsController). Served without the /api scope like the other crawler/share pages,
  # cached at the edge for 24h, and rendered as SVG — see ShareCard for why (no headless
  # browser or ImageMagick at runtime).
  get "share-cards/verified/:user_id.:format", to: "share_cards#verified", constraints: { format: /svg/ }
  get "share-cards/verified/:user_id/landscape.:format", to: "share_cards#landscape", constraints: { format: /svg/ }

  scope :api do
    get "health", to: "health#show"
    get "live", to: "health#show"
    get "readiness", to: "health#readiness"
    post "auth/register", to: "auth#register"
    post "auth/login", to: "auth#login"
    post "auth/logout", to: "auth#logout"
    post "auth/request-email-verification", to: "auth#request_verification"
    post "auth/verify-email", to: "auth#verify_email"
    post "auth/resend-verification", to: "auth#resend_verification"
    post "auth/forgot-password", to: "auth#forgot_password"
    get "auth/reset-password/check", to: "auth#check_reset_password_token"
    post "auth/reset-password", to: "auth#reset_password"
    post "auth/otp/request", to: "auth#otp_request"
    post "auth/otp/verify", to: "auth#otp_verify"
    post "auth/phone-otp/request", to: "auth#phone_otp_request"
    post "auth/phone-otp/verify", to: "auth#phone_otp_verify"
    post "auth/second-factor", to: "auth#second_factor"
    get "auth/methods", to: "auth#sign_in_methods"
    post "auth/exchange", to: "auth#exchange"
    post "auth/connect-ticket", to: "auth#connect_ticket"
    delete "auth/connections/:id", to: "auth#destroy_connection"
    get "me", to: "auth#me"
    get "me/identities", to: "identities#index"
    get "me/referral-code", to: "referrals#show"
    put "me/email-preferences", to: "notifications#update_email_preferences"
    get "push/config", to: "push#settings"
    post "push/subscriptions", to: "push#subscribe"
    delete "push/subscriptions", to: "push#unsubscribe"
    get "push/preferences", to: "push#preferences"
    put "push/preferences", to: "push#update_preferences"
    get "account/export", to: "account#export"
    delete "account", to: "account#destroy"
    patch "account/name", to: "account#update_name"
    post "account/email/request", to: "account#request_email_change"
    post "account/email/confirm", to: "account#confirm_email_change"
    post "account/password", to: "account#change_password"
    put "profile", to: "profiles#update"
    post "profile/whatsapp-consent", to: "profiles#whatsapp_consent"
    post "onboarding/starter", to: "onboarding#starter"
    post "link-previews", to: "link_previews#create"
    post "link-import/draft", to: "link_import#draft"
    post "library/import", to: "library_imports#create"
    get "public/stats", to: "public_stats#show"

    get "jobs/limits", to: "jobs#limits"
    resources :jobs, only: %i[index show create] do
      member { post :apply }
    end
    get "saved-jobs", to: "jobs#saved"
    post "saved-jobs/:id", to: "jobs#save"
    delete "saved-jobs/:id", to: "jobs#unsave"
    resources :applications, only: %i[index destroy]
    resources :job_alerts, path: "job-alerts", only: %i[index create update destroy]

    namespace :employer do
      resources :jobs, only: %i[index update]
      resources :applications, only: %i[index update]
    end
    namespace :admin do
      get :health, to: "health#show"
      post "health/sentry-test", to: "health#sentry_test"
      get :stats, to: "stats#index"
      get :tester, to: "tester#index"
      get :account, to: "account#show"
      post "account/email/request", to: "account#request_email_change"
      post "account/email/confirm", to: "account#confirm_email_change"
      post "account/password", to: "account#change_password"
      get "users/lookup", to: "users#lookup"
      resources :users, only: %i[index update] do
        member do
          get :billing, path: "billing"
          post :grant_plan, path: "grant-plan"
          post :revoke_sessions, path: "revoke-sessions"
          post :confirm_email, path: "confirm-email"
          post :grant_early_access, path: "early-access"
          delete :revoke_early_access, path: "early-access"
        end
      end
      resources :jobs, only: %i[index update]
      resources :reviews, only: %i[index update]
      resources :verifications, only: %i[index update] do
        get :stats, on: :collection
        post :revoke, on: :member
      end
      resources :reports, only: %i[index update] do
        member do
          get :context
          post :moderate
        end
      end
      resources :problem_reports, path: "problem-reports", only: %i[index show update] do
        get :screenshot, on: :member
      end
      get :operations, to: "operations#show"
      get :audit, to: "operations#audit"
      get :subscriptions, to: "operations#subscriptions"
      get "promo-codes/export", to: "promo_codes#export", defaults: { format: "csv" }
      resources :promo_codes, path: "promo-codes", only: %i[index create update] do
        member { get :redemptions }
      end
      get "payments-open-email", to: "payments_open_emails#show"
      post "payments-open-email", to: "payments_open_emails#create"
      get "billing-attempts", to: "operations#billing_attempts"
      post "billing-attempts/:id/reconcile", to: "operations#reconcile_billing_attempt"
      resources :billing_events, path: "billing-events", only: %i[index show]
      get "invoices/export", to: "invoices#export", defaults: { format: "csv" }
      resources :invoices, only: :index
      get "ai/costs", to: "ai#costs"
      get "ai/usage", to: "ai#usage"
      post "ai/grants", to: "ai#create_grant"
      get :bookings, to: "operations#bookings"
      resources :refunds, only: %i[index update]
      get :funnel, to: "funnel#show"
      get :emails, to: "emails#show"
      post "search/reindex", to: "search#reindex"
      get "demo-data", to: "demo_data#index"
      post "demo-data", to: "demo_data#create"
      delete "demo-data", to: "demo_data#destroy_all"
      get "demo-data/jobs/:id", to: "demo_data#job_status"
      delete "demo-data/:batch", to: "demo_data#destroy"
      get "urgent-requests", to: "urgent_requests#index"
      get "urgent-requests/:id/candidates", to: "urgent_requests#candidates"
      post "urgent-requests/:id/notify", to: "urgent_requests#notify"
      patch "urgent-requests/:id", to: "urgent_requests#update"
      resources :stage_posts, path: "stage-posts", only: %i[index destroy] do
        member do
          post :pin
          post :unpin
          post :feature
        end
      end
    end

    resources :portfolio, only: %i[index create update destroy], controller: "portfolio"
    # Portfolios are views over the owner's work samples, resumes views over the career record.
    resources :portfolios, only: %i[index show create update destroy] do
      collection { post :draft }
      member do
        post :default, action: :make_default
        post :reset
        put "items/:itemId", action: :set_item
      end
    end
    get "public/portfolios/:slug", to: "portfolios#public_show"
    resources :career_entries, path: "career-entries", only: %i[index create update destroy]
    resources :resumes, only: %i[index show create update destroy] do
      member do
        post :default, action: :make_default
        post :reset
        put "entries/:entryId", action: :set_entry
      end
    end
    resources :suggestions, only: :index do
      collection { post "accept-all", action: :accept_all }
      member do
        post :accept
        post :reject
      end
    end
    get "pages/:type/:id/jobs", to: "pages#jobs"
    get "notifications/unread", to: "notifications#unread"
    post "notifications/read-all", to: "notifications#read_all"
    get "notifications/preferences", to: "notifications#preferences"
    patch "notifications/preferences", to: "notifications#update_preferences"
    get "notifications/unsubscribe", to: "notifications#unsubscribe"
    post "notifications/unsubscribe", to: "notifications#unsubscribe"
    get "notifications/unsubscribe/preferences", to: "notifications#unsubscribe_status"
    patch "notifications/unsubscribe/preferences", to: "notifications#unsubscribe_update"
    post "email/webhook/brevo", to: "email_webhooks#brevo"
    resources :notifications, only: %i[index update]
    resources :reports, only: :create
    post "problem-reports", to: "problem_reports#create"
    resources :verification_requests, path: "verification-requests", only: :create
    resources :reviews, only: %i[index create]
    resources :resources, only: :index
    get "taxonomy", to: "catalog#taxonomy"
    get "legal/policy", to: "legal#policy"
    post "events", to: "events#create"
    resources :invoices, only: :show
    get "ai/status", to: "ai#status"
    post "ai/suggest", to: "ai#suggest"
    get "ai/autocomplete", to: "ai#autocomplete"
    get "ai/usage", to: "ai#usage"
    get "ai/pricing", to: "ai#pricing"
    post "ai/topups", to: "ai/billing#create_topup"
    post "ai/topups/verify", to: "ai/billing#verify_topup"
    post "ai/plus/subscribe", to: "ai/billing#subscribe_plus"
    get "dashboard", to: "dashboard#show"
    get "search", to: "search#index"
    get "search/status", to: "search#status"
    get "search/suggest", to: "search#suggest"
    post "cable/ticket", to: "cable_tickets#create"
    post "uploads/presign", to: "uploads#presign"
    put "uploads/local", to: "uploads#local"
    post "uploads/:id/complete", to: "uploads#complete", as: :complete_upload
    delete "uploads/:id", to: "uploads#destroy", as: :upload
    get "public/talent", to: "talent#public_index"
    get "public/talent/:id", to: "talent#public_show"
    get "public/hire-pages/popular-searches", to: "hire_pages#popular_searches"
    get "public/hire-pages/:role/:city", to: "hire_pages#show"
    get "public/rates/:city", to: "rates#show"
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
    # :id is the blocked user's id.
    resources :blocks, only: %i[create destroy], controller: "user_blocks"
    get "public/acts", to: "acts#public_index"
    get "public/acts/:id", to: "acts#public_show"
    get "acts/me", to: "acts#mine"
    resources :acts, only: %i[index show create update destroy] do
      member do
        post :members, to: "acts#add_member"
        delete "members/:member_id", to: "acts#remove_member"
        post :leave, to: "acts#leave"
        get :invitees, to: "act_invites#search"
        get :invites, to: "act_invites#index"
        post :invites, to: "act_invites#create"
        post "invites/:invite_id/resend", to: "act_invites#resend"
        delete "invites/:invite_id", to: "act_invites#revoke"
      end
    end
    # Bandmate invites, from the invitee's side. Link visitors use the token; signed-in musicians can also answer by id.
    get "act-invites/mine", to: "act_invites#mine"
    get "act-invites/preview", to: "act_invites#preview"
    post "act-invites/accept", to: "act_invites#accept"
    post "act-invites/decline", to: "act_invites#decline"
    post "act-invites/:id/accept", to: "act_invites#accept"
    post "act-invites/:id/decline", to: "act_invites#decline"
    get "bookings/limits", to: "bookings#limits"
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
    resources :urgent_requests, path: "urgent-requests", only: %i[index show create update] do
      member do
        post :respond
        post :accept
        get :responses
        get "token-action", to: "urgent_requests#action_from_token"
      end
    end
    resources :vouches, only: %i[index create]
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
    namespace :stage do
      get "feed", to: "feed#index"
      get "events", to: "events#index"
      get "authors/:type/:authorId/posts", to: "posts#by_author"
      get "authors/:type/:id", to: "authors#show"
      get "authors/:type/:id/followers", to: "follows#followers"
      get "authors/:type/:id/following", to: "follows#following"
      get "tags/:tag", to: "tags#show"
      post "follows", to: "follows#create"
      delete "follows/:type/:id", to: "follows#destroy"
      delete "comments/:id", to: "post_comments#destroy"
      resources :posts, only: %i[create show update destroy] do
        member do
          post :applause, to: "applause#create"
          delete :applause, to: "applause#destroy"
          get :ics, to: "events#ics"
        end
        resources :comments, only: %i[index create], controller: "post_comments"
      end
    end
    namespace :billing do
      get :plans, to: "billing#plans"
      get :subscription, to: "billing#subscription"
      post :checkout, to: "billing#checkout"
      post :cancel, to: "billing#cancel"
      get "cancel-link", to: "billing#verify_cancel_link"
      post "codes/validate", to: "codes#validate"
      get :profile, to: "profiles#show"
      put :profile, to: "profiles#update"
      resources :invoices, only: %i[index show]
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
