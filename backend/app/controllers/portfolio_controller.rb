class PortfolioController < ApplicationController
  before_action -> { authenticate!("jobseeker") }

  def index = render(json: { items: current_user.portfolio_items.order(featured: :desc, sort_order: :asc, created_at: :desc).limit(200).map(&:api_json) })

  def create
    item = current_user.portfolio_items.create!(item_params)
    audit!("portfolio.create", item)
    render json: { id: item.id, item: item.api_json }, status: :created
  end

  def update
    item = current_user.portfolio_items.find(params[:id])
    item.update!(item_params)
    render json: { item: item.api_json }
  end

  def destroy
    current_user.portfolio_items.find(params[:id]).destroy!
    render json: { ok: true }
  end

  private

  def item_params
    raw = params.permit(:type, :title, :url, :description, :creditedAs, :year, :featured, :thumbnailUrl, :waveformUrl, :sortOrder, :visibility,
      tags: [], genres: [], roles: [], instruments: [], mediaMetadata: {}).to_h.transform_keys { _1.underscore }
    raw["kind"] = raw.delete("type") if raw.key?("type")
    raw
  end
end
