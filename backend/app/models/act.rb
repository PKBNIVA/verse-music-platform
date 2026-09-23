class Act < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :act_members, dependent: :destroy
  has_many :booking_requests, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
  attribute :languages, :json, default: -> { [] }
  attribute :event_types, :json, default: -> { [] }
  validates :tech_rider_url, :hospitality_rider_url, :promo_url, safe_http_url: true, allow_blank: true
  def api_json = attributes.merge(members: act_members.map(&:api_json), ownerName: owner.name, ownerVerified: owner.profile&.verified || false)
end
