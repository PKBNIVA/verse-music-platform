FROM ruby:3.3.6-slim AS build

RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev git && rm -rf /var/lib/apt/lists/*
WORKDIR /rails
COPY backend/Gemfile ./
RUN bundle config set without "development test" && bundle install
COPY backend/ .

FROM ruby:3.3.6-slim
RUN apt-get update -qq && apt-get install --no-install-recommends -y libpq5 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /rails
ENV RAILS_ENV=production RAILS_LOG_TO_STDOUT=true RAILS_SERVE_STATIC_FILES=false BUNDLE_WITHOUT="development:test"
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
RUN useradd rails --create-home --shell /bin/bash && chown -R rails:rails db log storage tmp
USER rails
EXPOSE 3000
CMD ["bash", "-lc", "bin/rails db:prepare && bundle exec puma -C config/puma.rb"]
