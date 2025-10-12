FROM ruby:3.4.7-slim

WORKDIR /app

# Install PostgreSQL client libraries
RUN apt-get update && apt-get install -y \
    libpq-dev \
    build-essential \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

RUN bundle install --without development test

COPY . .

EXPOSE 5051

CMD ["bundle", "exec", "ruby", "gateway_server.rb"]
