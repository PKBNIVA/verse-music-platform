# Rails 8.1 framework defaults, adopted one by one while `config.load_defaults` stays
# at 7.2 (see docs/RAILS8_UPGRADE.md). Every 8.1 default is listed; each enabled line
# carries the reason it is safe for this API-only app. Once every line is enabled,
# delete this file and bump `config.load_defaults`.

###
# `render json:` stops HTML-escaping `<`, `>`, `&` (and U+2028/U+2029).
# ENABLED: responses are application/json consumed via fetch()/JSON.parse by the SPA;
# nothing embeds API JSON inside HTML, so the escaping only cost bytes and CPU.
# Parsed values are identical either way.
Rails.configuration.action_controller.escape_json_responses = false

###
# ActiveSupport JSON encoding stops escaping U+2028/U+2029 (valid in JS strings since
# ES2019). ENABLED: same reasoning; JSON is only parsed, never inlined into <script>.
Rails.configuration.active_support.escape_js_separators_in_json = false

###
# `#first`/`#last` etc. raise when a relation has no order and the model has no
# primary key / implicit_order_column to fall back on.
# ENABLED: the only key-less models (OrganizationMember, SavedJob, TalentFolderMember,
# TalentShortlist, UrgentRequestResponse) are never read with order-dependent finders
# (grep + full suite); the old behaviour is deprecated and removed in 8.2.
Rails.configuration.active_record.raise_on_missing_required_finder_order_columns = true

###
# `redirect_to "example.com"` (relative path without a leading slash) raises instead
# of logging. ENABLED: the API never redirects; raising is the safer failure mode.
Rails.configuration.action_controller.action_on_path_relative_redirect = :raise

###
# Ruby-parser based template dependency tracking. ENABLED: no templates (API only).
Rails.configuration.action_view.render_tracker = :ruby

###
# Hidden form fields omit autocomplete="off". ENABLED: no forms (API only).
Rails.configuration.action_view.remove_hidden_field_autocomplete = true
