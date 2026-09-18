class ResourcesController < ApplicationController
  def index = render(json: { resources: CareerResource.where(status: "published").order(created_at: :desc) })
end
