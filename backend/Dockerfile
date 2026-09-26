# Build context is the repository root (railway.toml: dockerfilePath = "backend/Dockerfile").
# Ignore rules live in backend/Dockerfile.dockerignore (BuildKit reads <Dockerfile>.dockerignore).
FROM ruby:3.3.6-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_FROZEN=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test"

FROM base AS build
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev git && rm -rf /var/lib/apt/lists/*
COPY backend/Gemfile backend/Gemfile.lock ./
# Install the exact Bundler recorded in Gemfile.lock, then exactly the locked gems.
# BUNDLE_DEPLOYMENT/BUNDLE_FROZEN make the build fail if Gemfile and Gemfile.lock disagree.
RUN gem install bundler -v "$(tail -n 1 Gemfile.lock | tr -d ' ')" --no-document \
  && bundle install \
  && rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git
COPY backend/ .

FROM base
RUN apt-get update -qq && apt-get install --no-install-recommends -y libpq5 curl gosu && rm -rf /var/lib/apt/lists/*
ENV RAILS_LOG_TO_STDOUT=true RAILS_SERVE_STATIC_FILES=false
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
RUN useradd rails --create-home --shell /bin/bash \
  && mkdir -p db log storage tmp/pids \
  && chown -R rails:rails db log storage tmp
EXPOSE 3000
CMD ["bash", "-lc", "chown -R rails:rails storage tmp log && exec gosu rails bash -lc 'bin/rails db:prepare && exec bundle exec puma -C config/puma.rb'"]
