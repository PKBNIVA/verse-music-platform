class CatalogController < ApplicationController
  def taxonomy
    render json: {
      opportunityKinds: %w[job gig audition session tour internship collaboration],
      functionAreas: ["Performance", "Production", "Audio Engineering", "Live & Touring", "Technical", "Management"],
      workplaces: %w[onsite hybrid remote travel], currencies: %w[INR USD EUR GBP]
    }
  end
end
