class Act < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :act_members, dependent: :destroy
  has_many :booking_requests, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
  attribute :languages, :json, default: -> { [] }
  attribute :event_types, :json, default: -> { [] }
  validates :tech_rider_url, :hospitality_rider_url, :promo_url, safe_http_url: true, allow_blank: true
  validates :name, :act_type, :city, presence: true
  validates :status, inclusion: { in: %w[active inactive draft] }
  validates :lineup_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_fee, :max_fee, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :fee_range_is_valid
  def api_json = attributes.merge(members: act_members.map(&:api_json), ownerName: owner.name, ownerVerified: owner.profile&.verified || false)

  private

  def fee_range_is_valid
    errors.add(:max_fee, "must be at least the minimum fee") if min_fee && max_fee && max_fee < min_fee
  end
end
