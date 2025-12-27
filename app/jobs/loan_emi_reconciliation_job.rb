# frozen_string_literal: true

# Job to reconcile EMI payments across all loan accounts in a family
# This matches bank statement debits to loan EMI entries
class LoanEmiReconciliationJob < ApplicationJob
  queue_as :default

  def perform(family_id)
    family = Family.find_by(id: family_id)
    return unless family

    Rails.logger.info("LoanEmiReconciliationJob: Starting reconciliation for family #{family_id}")
    
    reconciler = LoanEmiReconciler.new(family)
    results = reconciler.reconcile_all

    Rails.logger.info("LoanEmiReconciliationJob: Completed - Matched: #{results[:matched].count}, Unmatched: #{results[:unmatched].count}")
    
    results
  end
end
