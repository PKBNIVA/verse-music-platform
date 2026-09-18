module Admin
  class BaseController < ApplicationController
    before_action -> { authenticate!("admin") }
  end
end
