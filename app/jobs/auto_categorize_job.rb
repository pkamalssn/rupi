class AutoCategorizeJob < ApplicationJob
  queue_as :medium_priority

  def perform(family, transaction_ids: [], rule_run_id: nil, import_id: nil)
    # If this is tied to an import, update its status
    import = Import.find_by(id: import_id) if import_id.present?
    
    begin
      modified_count = family.auto_categorize_transactions(transaction_ids)

      # If this job was part of a rule run, report back the modified count
      if rule_run_id.present?
        rule_run = RuleRun.find_by(id: rule_run_id)
        rule_run&.complete_job!(modified_count: modified_count)
      end
      
      # If this job was part of an import, mark categorization complete
      if import.present?
        import.complete_categorization!(modified_count)
        
        # Broadcast update via Turbo Stream if available
        broadcast_import_update(import)
      end
      
    rescue => e
      Rails.logger.error("AutoCategorizeJob failed: #{e.message}")
      
      # Mark import categorization as failed
      import&.fail_categorization!(e.message)
      
      raise e  # Re-raise to let job retry mechanism handle it
    end
  end
  
  private
  
  def broadcast_import_update(import)
    # Broadcast Turbo Stream update for live UI refresh
    Turbo::StreamsChannel.broadcast_replace_to(
      "import_#{import.id}",
      target: "import_status",
      partial: "imports/status_update",
      locals: { import: import }
    )
  rescue => e
    # Don't fail the job if broadcast fails
    Rails.logger.warn("Failed to broadcast import update: #{e.message}")
  end
end
