class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  before_create :assign_public_id

  private

  def assign_public_id
    self.id ||= "#{self.class.name.underscore.gsub('/', '_').first(4)}_#{SecureRandom.uuid}" if has_attribute?(:id)
  end
end
