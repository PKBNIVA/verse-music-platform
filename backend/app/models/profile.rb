class Profile < ApplicationRecord
  self.primary_key = :user_id
  belongs_to :user

  JSON_FIELDS = %i[skills genres instruments languages credits open_to roles gear software].freeze
  JSON_FIELDS.each { |field| attribute field, :json, default: -> { [] } }
  validates :website, :portfolio_url, :company_website, safe_http_url: true, allow_blank: true

  def api_json
    attributes.except("user_id", "created_at", "updated_at", "email_notifications").transform_keys { _1.camelize(:lower) }
  end
end
