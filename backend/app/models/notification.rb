class Notification < ApplicationRecord
  belongs_to :user
  has_one :job_alert_delivery
end
