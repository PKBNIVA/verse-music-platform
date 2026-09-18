class EmailToken < ApplicationRecord
  belongs_to :user
  scope :usable, ->(purpose) { where(purpose:, used_at: nil).where("expires_at > ?", Time.current) }
end
