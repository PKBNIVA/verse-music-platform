class JobAlertDelivery < ApplicationRecord
  belongs_to :job_alert
  belongs_to :job
  belongs_to :notification, optional: true
end
