class AddCategorizationTrackingToImports < ActiveRecord::Migration[7.2]
  def change
    add_column :imports, :categorization_status, :string, default: nil
    add_column :imports, :categorization_job_id, :string
    add_column :imports, :categorized_count, :integer, default: 0
    add_column :imports, :total_to_categorize, :integer, default: 0
    
    add_index :imports, :categorization_status
  end
end
