Rails.application.config.filter_parameters += %i[password password_confirmation token authorization secret email razorpay_signature otp code]
Rails.application.config.filter_parameters += %i[body] # message bodies never reach request logs
