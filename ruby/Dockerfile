FROM ruby:3.3-slim

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Rakefile ./
RUN bundle install --without development test

COPY . .

ENV PORT=8080
EXPOSE 8080

CMD ["ruby", "bin/railsmith-api"]
