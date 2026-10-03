class Notification < ApplicationRecord
  belongs_to :user
  has_one :job_alert_delivery
  # Live badge refresh for the recipient (Realtime; polling is the fallback).
  after_create_commit { Realtime.notification_created(self) }
end
