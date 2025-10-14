# frozen_string_literal: true

require "httparty"

class PushNotificationService
  include HTTParty
  base_uri ENV.fetch("MICRO_GOPUSH_URL", "http://localhost:8080")

  def self.get_vapid_public_key
    response = get("/vapid-public-key")
    handle_response(response) do |json_response|
      json_response["publicKey"]
    end
  end

  def self.subscribe(subscription_data)
    # The micro-gopush service expects a JSON body like:
    # { "subscription": { "endpoint": "...", "keys": { "p256dh": "...", "auth": "..." } } }
    # The subscription_data from GraphQL already matches the inner structure.
    response = post("/subscribe", body: { subscription: subscription_data }.to_json, headers: { "Content-Type" => "application/json" })
    handle_response(response) do
      { success: true, message: "Subscription successful" }
    end
  end

  def self.notify_all
    response = post("/notify-all")
    handle_response(response) do
      { success: true, message: "Notification sent to all subscribers" }
    end
  end

  private

  def self.handle_response(response)
    if response.success?
      yield response.parsed_response if block_given?
    else
      Rails.logger.error "PushNotificationService Error: #{response.code} - #{response.body}"
      raise "PushNotificationService Error: #{response.code} - #{response.body}"
    end
  rescue HTTParty::Error => e
    Rails.logger.error "PushNotificationService Network Error: #{e.message}"
    raise "PushNotificationService Network Error: #{e.message}"
  end
end
