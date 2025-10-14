# frozen_string_literal: true

module Types
  class VapidPublicKeyType < Types::BaseScalar
    description "A VAPID public key string"

    def self.coerce_input(input_value, context)
      # Assuming the input is always a string for now
      input_value.to_s
    end

    def self.coerce_result(ruby_value, context)
      ruby_value.to_s
    end
  end
end
