class Session < ApplicationRecord
  belongs_to :user
  scope :active, -> { where("expires_at > ?", Time.current) }
end
