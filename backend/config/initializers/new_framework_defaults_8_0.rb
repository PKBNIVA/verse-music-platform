# Rails 8.0 framework defaults, adopted one by one while `config.load_defaults` stays
# at 7.2 (see docs/RAILS8_UPGRADE.md). Every 8.0 default is listed; each enabled line
# carries the reason it is safe for this API-only app. Once every line is enabled,
# delete this file and bump `config.load_defaults`.

###
# `to_time` keeps the receiver's full time zone instead of only its UTC offset.
# ALWAYS ON: Rails 8.1 hard-codes :zone and deprecates the setting itself, so it must
# not be set at all. (On 8.0 it had to be set to :zone in config/application.rb.)
# The app stores and serialises UTC timestamps (`Time.current`, `iso8601`), so zone
# vs. offset makes no observable difference.
# Rails.application.config.active_support.to_time_preserves_timezone = :zone

###
# When a client sends both If-Modified-Since and If-None-Match, only the ETag is
# considered (RFC 7232 section 6).
# ENABLED: the API issues no conditional-GET responses (no fresh_when/stale?);
# this only makes Rails follow the RFC if one is added later.
Rails.application.config.action_dispatch.strict_freshness = true

###
# Global 1s Regexp.timeout guards against ReDoS on user-controlled input.
# ENABLED: all app regexes are simple validation patterns over short strings; a
# match taking >1s would already be a bug. Raises Regexp::TimeoutError if hit.
Regexp.timeout = 1
