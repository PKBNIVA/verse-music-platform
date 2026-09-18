class Review < ApplicationRecord
  belongs_to :author, class_name: "User"
  belongs_to :employer, class_name: "User"
  validates :rating, inclusion: 1..5
end
