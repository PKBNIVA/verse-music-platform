Rails.application.config.filter_parameters += %i[password password_confirmation token authorization secret email razorpay_signature otp code]
Rails.application.config.filter_parameters += %i[body] # message bodies never reach request logs
# Rails 8 generator defaults not already covered above (partial matches; logs and inspect only).
Rails.application.config.filter_parameters += %i[passw _key crypt salt certificate ssn cvv cvc]
