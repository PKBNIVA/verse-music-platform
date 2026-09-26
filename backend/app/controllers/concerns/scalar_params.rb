# Rejects array/hash values where a controller expects a plain string (e.g. `?q[]=a`),
# which would otherwise reach SQL/String helpers and raise a 500.
module ScalarParams
  extend ActiveSupport::Concern

  private

  # Renders 400 and returns false when any of `keys` holds a non-scalar value.
  def require_scalar_params!(*keys)
    bad = keys.select { |key| params.key?(key) && (params[key].is_a?(Array) || params[key].is_a?(ActionController::Parameters) || params[key].is_a?(Hash)) }
    return true if bad.empty?
    render_error("#{bad.map(&:to_s).join(', ')} must be #{bad.one? ? 'a single value' : 'single values'}.", :bad_request, "INVALID_PARAMETER")
    false
  end

  # A list of short strings from an array of scalars or a single scalar; nil for anything else.
  def string_list_param(key, max: 20)
    value = params[key]
    return [] if value.blank?
    values = value.is_a?(Array) ? value : (value.is_a?(String) ? [value] : nil)
    return nil if values.nil? || values.any? { _1.is_a?(Array) || _1.is_a?(ActionController::Parameters) || _1.is_a?(Hash) }
    values.map { _1.to_s.strip }.reject(&:blank?).uniq.first(max)
  end
end
