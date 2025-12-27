# frozen_string_literal: true

# Migration to add ActiveStorage attachment for statement files
class AddStatementFileToImports < ActiveRecord::Migration[7.2]
  def change
    # ActiveStorage uses separate tables (active_storage_blobs, active_storage_attachments)
    # No need to add columns directly - we just need to ensure we can associate files
    # The association is defined in the model with `has_one_attached :statement_file`

    # Note: ActiveStorage tables should already exist in the schema
    # If not, you may need to run: rails active_storage:install
  end
end
