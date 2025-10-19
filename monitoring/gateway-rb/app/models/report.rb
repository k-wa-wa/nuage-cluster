# frozen_string_literal: true

class Report < ApplicationRecord
  self.table_name = "reports"
  # Exclude seq_id from being accessible or returned
  # This is a simple ActiveRecord model, no special logic needed for excluding seq_id from being returned
  # as GraphQL type definition already handles it.
end
