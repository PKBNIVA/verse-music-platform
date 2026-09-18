class ApplicationEvent < ApplicationRecord
  belongs_to :application
  belongs_to :actor, class_name: "User", optional: true
end
