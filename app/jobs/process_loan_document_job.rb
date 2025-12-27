# frozen_string_literal: true

class ProcessLoanDocumentJob < ApplicationJob
  queue_as :default

  def perform(loan_document_import)
    loan_document_import.process_document!
  end
end
