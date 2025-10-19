# frozen_string_literal: true

require "kubernetes/kubernetes_client"

module KubernetesService
  class << self
    def get_application_lists
      client = Kubernetes::KubernetesClient.new()
      client.get_application_lists
    end
  end
end
