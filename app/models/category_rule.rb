# frozen_string_literal: true

# CategoryRule stores learned rules for auto-categorizing transactions.
# 
# This model enables "Rule Authoring via AI":
# 1. When AI categorizes a new merchant/pattern, a rule is proposed
# 2. Rules can be manually created/edited by users
# 3. Future transactions matching rules are categorized deterministically (faster, no AI cost)
#
# Flow:
# 1. Unknown merchant appears in statement
# 2. AI proposes category + rule pattern
# 3. Rule is stored in CategoryRule
# 4. Future transactions become deterministic (no AI call needed)
#
# User can:
# - "Why was this categorized?" -> Shows matching rule
# - "Edit rule" -> Modify pattern or category
#
class CategoryRule < ApplicationRecord
  belongs_to :family
  belongs_to :category

  # Match types for pattern matching
  MATCH_TYPES = %w[contains exact regex starts_with ends_with].freeze
  
  # Sources of rules
  SOURCES = %w[auto manual ai system].freeze

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :pattern, uniqueness: { scope: :family_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :by_confidence, -> { order(confidence: :desc, times_matched: :desc) }
  scope :by_pattern_length, -> { order(Arel.sql("LENGTH(pattern) DESC")) }  # More specific patterns first

  # Find a matching rule for a transaction description
  def self.find_matching_rule(description, family:)
    return nil if description.blank?
    
    description_lower = description.downcase.strip
    
    # Get active rules for this family, ordered by confidence and specificity
    active.where(family: family).by_confidence.by_pattern_length.find do |rule|
      rule.matches?(description_lower)
    end
  end
  
  # Find category for a description using rules
  def self.categorize_by_rules(description, family:)
    rule = find_matching_rule(description, family: family)
    return nil unless rule
    
    # Increment match counter (async to avoid blocking)
    rule.increment!(:times_matched)
    
    rule.category
  end

  # Check if this rule matches a description
  def matches?(description)
    return false if description.blank?
    
    desc = description.downcase.strip
    pattern_lower = pattern.downcase.strip
    
    case match_type
    when "exact"
      desc == pattern_lower
    when "starts_with"
      desc.start_with?(pattern_lower)
    when "ends_with"
      desc.end_with?(pattern_lower)
    when "regex"
      begin
        desc.match?(Regexp.new(pattern, Regexp::IGNORECASE))
      rescue RegexpError
        false
      end
    else # contains (default)
      desc.include?(pattern_lower)
    end
  end

  # Create a rule from an AI categorization
  def self.create_from_ai_categorization(description:, category:, family:, confidence: 0.9)
    # Extract a clean pattern from description
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    
    # Check if rule already exists
    existing = find_by(family: family, pattern: pattern.downcase)
    if existing
      existing.increment!(:times_matched)
      return existing
    end
    
    create(
      family: family,
      category: category,
      pattern: pattern.downcase,
      match_type: "contains",
      source: "ai",
      confidence: confidence,
      merchant_name: extract_merchant_name(description)
    )
  end

  # Learn a rule from user's manual categorization
  def self.learn_from_user(transaction:, category:)
    description = transaction.entry.name
    return nil if description.blank?
    
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    
    existing = find_by(family: transaction.family, pattern: pattern.downcase)
    if existing
      # User is confirming/correcting - update category and boost confidence
      existing.update(category: category, confidence: [existing.confidence + 0.1, 1.0].min, source: "manual")
      existing.increment!(:times_matched)
      return existing
    end
    
    create(
      family: transaction.family,
      category: category,
      pattern: pattern.downcase,
      match_type: "contains",
      source: "manual",
      confidence: 1.0,  # User-created rules have highest confidence
      merchant_name: extract_merchant_name(description)
    )
  end

  # Get explanation for why this rule matched
  def explanation
    case source
    when "manual"
      "You categorized similar transactions as #{category.name}"
    when "ai"
      "AI learned this pattern from your statement - #{times_matched} matches"
    when "system"
      "Default categorization rule"
    else
      "Auto-detected pattern"
    end
  end

  private

  # Extract a meaningful pattern from a transaction description
  def self.extract_pattern(description)
    return nil if description.blank?
    
    # Remove common noise
    pattern = description.dup
    
    # Remove transaction IDs, dates, reference numbers
    pattern = pattern.gsub(/\b[A-Z0-9]{10,}\b/, "")  # Long alphanumeric codes
    pattern = pattern.gsub(/\b\d{10,}\b/, "")         # Long numbers
    pattern = pattern.gsub(/\d{2}[-\/]\d{2}[-\/]\d{2,4}/, "")  # Dates
    pattern = pattern.gsub(/ref\s*:?\s*\S+/i, "")     # Reference numbers
    pattern = pattern.gsub(/upi\s*ref\s*no\s*\S+/i, "")  # UPI refs
    
    # Extract merchant-like patterns
    pattern = pattern.strip.split(/\s+/).reject { |w| w.length < 3 }.first(3).join(" ")
    
    pattern.presence
  end

  def self.extract_merchant_name(description)
    return nil if description.blank?
    
    # Try to extract merchant name from common patterns
    # e.g., "SWIGGY INSTAMART" from "UPI-SWIGGY INSTAMART-REF12345"
    
    # Split by common delimiters
    parts = description.split(/[-_|\/]/)
    
    # Find the most "merchant-like" part (capitalized, reasonable length)
    parts.find { |p| p.strip.length >= 4 && p.strip.length <= 30 && p.match?(/[A-Za-z]/) }&.strip
  end
end
