class PortfolioItem < ApplicationRecord
  belongs_to :user
  attribute :tags, :json, default: -> { [] }
  attribute :genres, :json, default: -> { [] }
  attribute :roles, :json, default: -> { [] }
  attribute :instruments, :json, default: -> { [] }
  attribute :media_metadata, :json, default: -> { {} }
  validates :title, :kind, :url, presence: true
  validates :url, :thumbnail_url, :waveform_url, safe_http_url: true, allow_blank: true

  def api_json = attributes.transform_keys { _1.camelize(:lower) }.merge(type: kind)
end
