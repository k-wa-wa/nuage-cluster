# frozen_string_literal: true

require "base64"
require "yaml"
require "kubeclient"

module Kubernetes
  class KubernetesConfig
    def self.load_config
      if ENV["KUBE_CONFIG"]
       Kubeclient::Config.read(ENV["KUBE_CONFIG"])
      else
       Kubeclient::Config.in_cluster
      end
    rescue StandardError => e
      Rails.logger.error "Error loading Kubernetes config: #{e.message}"
      raise GraphQL::ExecutionError, "Failed to load Kubernetes configuration: #{e.message}"
    end
  end
end
