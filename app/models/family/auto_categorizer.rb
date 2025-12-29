class Family::AutoCategorizer
  Error = Class.new(StandardError)
  
  # Maximum transactions per LLM request (gemini-3-flash-preview with 1M context easily handles 200+)
  BATCH_SIZE = 200
  
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
        category_name = auto_categorization&.category_name
        
        next if category_name.blank? || category_name == "null"
        
        # Handle NEW: prefix for AI-suggested categories
        if category_name.start_with?("NEW:")
          new_category_name = category_name.sub(/^NEW:/, "").strip
          category = find_or_create_category(new_category_name, transaction)
          Rails.logger.info("AI suggested new category: '#{new_category_name}' for '#{transaction.entry.name}'")
        else
          # Existing category lookup
          category = categories_input.find { |c| c[:name] == category_name }&.dig(:id)
          category = Category.find_by(id: category) if category
        end
        
        next unless category

        was_modified = transaction.enrich_attribute(
          :category_id,
          category.id,
          source: "ai"
        )
        transaction.lock_attr!(:category_id)
        total_modified += 1 if was_modified
        
        # Create rule for future transactions (both existing and new categories)
        if was_modified
          CategoryRule.create_from_ai_categorization(
            description: transaction.entry.name,
            category: category,
            family: family,
            confidence: 0.85
          )
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
    
    # Find or create a category suggested by AI
    # Returns the Category record
    def find_or_create_category(category_name, transaction)
      # Clean up the name
      clean_name = category_name.to_s.strip.titleize
      return nil if clean_name.blank?
      
      # Determine classification based on transaction amount
      # Negative amount = expense (money going out)
      # Positive amount = income (money coming in)
      classification = transaction.entry.amount.negative? ? "expense" : "income"
      
      # Try to find existing category first (case-insensitive)
      existing = family.categories.where("LOWER(name) = ?", clean_name.downcase).first
      return existing if existing
      
      # Create new category
      new_category = family.categories.create!(
        name: clean_name,
        classification: classification,
        color: random_category_color
      )
      
      Rails.logger.info("Created new AI-suggested category: #{clean_name} (#{classification})")
      new_category
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to create category '#{clean_name}': #{e.message}")
      nil
    end
    
    # Random color for new categories
    def random_category_color
      colors = %w[
        #EF4444 #F97316 #F59E0B #EAB308 #84CC16 #22C55E #10B981 
        #14B8A6 #06B6D4 #0EA5E9 #3B82F6 #6366F1 #8B5CF6 #A855F7 
        #D946EF #EC4899 #F43F5E
      ]
      colors.sample
    end
end

