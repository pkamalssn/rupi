class Family::AutoCategorizer
  Error = Class.new(StandardError)
  
  # Maximum transactions per LLM request (Gemini/OpenAI limit)
  BATCH_SIZE = 25
  
  def initialize(family, transaction_ids: [])
    @family = family
    @transaction_ids = transaction_ids
  end

  def auto_categorize
    raise Error, "No LLM provider for auto-categorization" unless llm_provider

    if scope.none?
      Rails.logger.info("No transactions to auto-categorize for family #{family.id}")
      return 0
    else
      Rails.logger.info("Auto-categorizing #{scope.count} transactions for family #{family.id}")
    end

    categories_input = user_categories_input

    if categories_input.empty?
      Rails.logger.error("Cannot auto-categorize transactions for family #{family.id}: no categories available")
      return 0
    end

    # =====================================================
    # BATCHING: Process transactions in groups of 25
    # This avoids the LLM token limit while ensuring ALL
    # transactions get categorized
    # =====================================================
    total_modified = 0
    all_transactions = scope.to_a
    
    all_transactions.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      Rails.logger.info("Processing batch #{batch_index + 1}/#{(all_transactions.size.to_f / BATCH_SIZE).ceil} (#{batch.size} transactions)")
      
      batch_input = batch.map do |transaction|
        {
          id: transaction.id,
          amount: transaction.entry.amount.abs,
          classification: transaction.entry.classification,
          description: [ transaction.entry.name, transaction.entry.notes ].compact.reject(&:empty?).join(" "),
          merchant: transaction.merchant&.name
        }
      end
      
      result = llm_provider.auto_categorize(
        transactions: batch_input,
        user_categories: categories_input,
        family: family
      )

      unless result.success?
        Rails.logger.error("Failed to auto-categorize batch #{batch_index + 1} for family #{family.id}: #{result.error.message}")
        next  # Continue with next batch instead of failing entirely
      end

      batch.each do |transaction|
        auto_categorization = result.data.find { |c| c.transaction_id == transaction.id }
        category_id = categories_input.find { |c| c[:name] == auto_categorization&.category_name }&.dig(:id)

        if category_id.present?
          was_modified = transaction.enrich_attribute(
            :category_id,
            category_id,
            source: "ai"
          )
          transaction.lock_attr!(:category_id)
          total_modified += 1 if was_modified
          
          # Create rule for future transactions
          if was_modified
            category = Category.find_by(id: category_id)
            if category
              CategoryRule.create_from_ai_categorization(
                description: transaction.entry.name,
                category: category,
                family: family,
                confidence: 0.85
              )
            end
          end
        end
      end
      
      Rails.logger.info("Batch #{batch_index + 1} complete: #{total_modified} total modified so far")
    end

    Rails.logger.info("Auto-categorization complete: #{total_modified} transactions categorized")
    total_modified
  end

  private
    attr_reader :family, :transaction_ids

    # Use Gemini as the primary LLM provider for auto-categorization
    def llm_provider
      Provider::Registry.get_provider(:gemini)
    end

    def user_categories_input
      family.categories.map do |category|
        {
          id: category.id,
          name: category.name,
          is_subcategory: category.subcategory?,
          parent_id: category.parent_id,
          classification: category.classification
        }
      end
    end

    def transactions_input
      scope.map do |transaction|
        {
          id: transaction.id,
          amount: transaction.entry.amount.abs,
          classification: transaction.entry.classification,
          description: [ transaction.entry.name, transaction.entry.notes ].compact.reject(&:empty?).join(" "),
          merchant: transaction.merchant&.name
        }
      end
    end

    def scope
      family.transactions.where(id: transaction_ids, category_id: nil)
                         .enrichable(:category_id)
                         .includes(:category, :merchant, :entry)
    end
end
