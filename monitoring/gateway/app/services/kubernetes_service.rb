# frozen_string_literal: true

require "kubernetes/kubernetes_config"
require "kubernetes/kubernetes_client"

module KubernetesService
  class << self
    def get_application_lists
      config = Kubernetes::KubernetesConfig.load_config
      client = Kubernetes::KubernetesClient.new(config)
      client.get_application_lists
    end
  end
end
