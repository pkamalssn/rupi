# frozen_string_literal: true

# CategoryRule stores learned rules for auto-categorizing transactions.
# 
# RULE LIFECYCLE:
# 1. AI creates rule as "candidate" (status: candidate, confidence: 0.65)
# 2. After N matches (default: 2), rule is auto-promoted to "active"
# 3. User confirmation immediately promotes to "active" (confidence: 0.95)
# 4. User override decreases confidence, may demote to "inactive"
# 5. Manual rules start at confidence 1.0 and status "active"
#
# PRECEDENCE (highest to lowest):
# 1. Manual rules (source: manual, weight: 100)
# 2. System rules (source: system, weight: 80)
# 3. AI-confirmed rules (source: ai, user_confirmed: true, weight: 70)
# 4. AI rules (source: ai, weight: 50)
#
# WITHIN SAME SOURCE:
# - exact > starts_with > ends_with > contains > regex
# - Longer patterns win (more specific)
# - Higher confidence wins
#
class CategoryRule < ApplicationRecord
  belongs_to :family
  belongs_to :category

  # Match types ordered by specificity (higher = more specific)
  MATCH_TYPES = {
    "exact" => 100,
    "starts_with" => 80,
    "ends_with" => 70,
    "contains" => 50,
    "regex" => 40
  }.freeze
  
  # Sources ordered by trust level (higher = more trusted)
  SOURCE_WEIGHTS = {
    "manual" => 100,
    "system" => 80,
    "ai" => 50,
    "auto" => 30
  }.freeze
  
  # Rule statuses
  STATUSES = %w[candidate active inactive].freeze
  
  # Promotion threshold: how many matches before candidate → active
  PROMOTION_THRESHOLD = 2
  
  # Confidence thresholds
  INITIAL_AI_CONFIDENCE = 0.65
  CONFIRMED_CONFIDENCE = 0.95
  MANUAL_CONFIDENCE = 1.0
  CONFIDENCE_INCREMENT = 0.05  # Per successful match
  CONFIDENCE_DECREMENT = 0.15  # Per user override
  MIN_CONFIDENCE = 0.3         # Below this, rule is demoted to inactive
  
  # Dangerous/generic keywords that need word-boundary matching
  GENERIC_PATTERNS = %w[
    hdfc icici axis sbi kotak
    paytm phonepe gpay upi
    jio airtel vi bsnl
    amazon flipkart
    transfer credit debit
    payment
  ].freeze

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES.keys }
  validates :source, inclusion: { in: SOURCE_WEIGHTS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :pattern, uniqueness: { scope: :family_id, case_sensitive: false }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(status: "active") }
  scope :candidates, -> { where(status: "candidate") }
  scope :by_priority, -> { order(priority: :desc, confidence: :desc) }

  before_validation :calculate_priority
  before_validation :set_defaults, on: :create

  # ==========================================
  # MAIN MATCHING LOGIC
  # ==========================================
  
  # Find the best matching rule for a transaction description
  def self.find_matching_rule(description, family:)
    return nil if description.blank?
    
    normalized = normalize_description(description)
    
    # Get active rules for this family, ordered by priority
    matching_rules = active.where(family: family).by_priority.select do |rule|
      rule.matches?(normalized)
    end
    
    # Return highest priority match
    matching_rules.first
  end
  
  # Find category for a description using rules
  def self.categorize_by_rules(description, family:)
    rule = find_matching_rule(description, family: family)
    return nil unless rule
    
    # Track the match and potentially promote
    rule.record_match!
    
    rule.category
  end
  
  # Normalize description for matching
  def self.normalize_description(description)
    return "" if description.blank?
    
    desc = description.dup
    
    # Remove common noise patterns
    desc = desc.gsub(/\b[A-Z0-9]{12,}\b/, "")           # Long alphanumeric codes (ref numbers)
    desc = desc.gsub(/\b\d{10,}\b/, "")                  # Long numbers (phone, account)
    desc = desc.gsub(/\d{2}[-\/]\d{2}[-\/]\d{2,4}/, "") # Dates
    desc = desc.gsub(/ref\s*:?\s*\S+/i, "")             # Reference patterns
    desc = desc.gsub(/upi\s*ref\s*no\s*\S+/i, "")       # UPI refs
    desc = desc.gsub(/[^\w\s]/, " ")                    # Punctuation → spaces
    desc = desc.gsub(/\s+/, " ")                        # Collapse whitespace
    
    desc.strip.downcase
  end

  # Check if this rule matches a description
  def matches?(normalized_description)
    return false if normalized_description.blank?
    
    pattern_lower = pattern.downcase.strip
    
    # For generic patterns, require word boundary matching
    if GENERIC_PATTERNS.any? { |g| pattern_lower.include?(g) }
      return word_boundary_match?(normalized_description, pattern_lower)
    end
    
    case match_type
    when "exact"
      normalized_description == pattern_lower
    when "starts_with"
      normalized_description.start_with?(pattern_lower)
    when "ends_with"
      normalized_description.end_with?(pattern_lower)
    when "regex"
      safe_regex_match?(normalized_description, pattern)
    else # contains (default)
      normalized_description.include?(pattern_lower)
    end
  end
  
  # Word-boundary matching for generic patterns
  def word_boundary_match?(description, pattern)
    # Match pattern as a whole word, not substring
    regex = Regexp.new("\\b#{Regexp.escape(pattern)}\\b", Regexp::IGNORECASE)
    description.match?(regex)
  rescue RegexpError
    description.include?(pattern)
  end
  
  def safe_regex_match?(description, pattern)
    description.match?(Regexp.new(pattern, Regexp::IGNORECASE))
  rescue RegexpError
    false
  end

  # ==========================================
  # MATCH TRACKING & PROMOTION
  # ==========================================
  
  def record_match!
    increment!(:times_matched)
    
    # Increase confidence (with cap)
    new_confidence = [confidence + CONFIDENCE_INCREMENT, 0.99].min
    update_column(:confidence, new_confidence)
    
    # Auto-promote candidates after threshold
    if status == "candidate" && times_matched >= PROMOTION_THRESHOLD
      promote_to_active!
      Rails.logger.info("CategoryRule promoted: pattern='#{pattern}' after #{times_matched} matches")
    end
    
    recalculate_priority!
  end
  
  def promote_to_active!
    update!(status: "active")
  end
  
  def demote_to_inactive!
    update!(status: "inactive")
  end
  
  # Called when user overrides this rule's categorization
  def record_override!
    increment!(:times_overridden)
    
    # Decrease confidence
    new_confidence = [confidence - CONFIDENCE_DECREMENT, 0].max
    update_column(:confidence, new_confidence)
    
    # Demote if confidence too low
    if new_confidence < MIN_CONFIDENCE
      demote_to_inactive!
      Rails.logger.warn("CategoryRule demoted: pattern='#{pattern}' confidence=#{new_confidence}")
    end
    
    recalculate_priority!
  end
  
  # User confirms this rule is correct
  def confirm!
    update!(
      confidence: [confidence, CONFIRMED_CONFIDENCE].max,
      status: "active",
      user_confirmed: true
    )
    recalculate_priority!
  end

  # ==========================================
  # PRIORITY CALCULATION
  # ==========================================
  
  def calculate_priority
    # Priority formula combines multiple factors:
    # priority = source_weight * 1000 + match_strength * 10 + pattern_specificity + confidence_bonus
    
    source_weight = SOURCE_WEIGHTS[source] || 30
    match_strength = MATCH_TYPES[match_type] || 50
    pattern_specificity = [pattern.to_s.length, 50].min  # Cap at 50 to prevent gaming
    confidence_bonus = (confidence * 10).round
    user_confirmed_bonus = user_confirmed? ? 200 : 0
    
    self.priority = (source_weight * 1000) + 
                    (match_strength * 10) + 
                    pattern_specificity + 
                    confidence_bonus +
                    user_confirmed_bonus
  end
  
  def recalculate_priority!
    calculate_priority
    update_column(:priority, priority)
  end

  # ==========================================
  # RULE CREATION
  # ==========================================

  # Create a rule from an AI categorization (starts as candidate)
  def self.create_from_ai_categorization(description:, category:, family:, confidence: nil)
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    return nil if pattern.length < 3  # Too short = too generic
    
    # Check for existing rule with same pattern
    existing = find_by(family: family, pattern: pattern.downcase)
    if existing
      existing.record_match!
      return existing
    end
    
    # Check for conflicting rules (same pattern, different category)
    # Don't create if there's already a manual/system rule
    conflicting = where(family: family)
                    .where("LOWER(pattern) = ?", pattern.downcase)
                    .where.not(category: category)
                    .exists?
    return nil if conflicting
    
    create(
      family: family,
      category: category,
      pattern: pattern.downcase,
      match_type: determine_match_type(pattern),
      source: "ai",
      status: "candidate",  # Starts as candidate, not active!
      confidence: confidence || INITIAL_AI_CONFIDENCE,
      merchant_name: extract_merchant_name(description),
      user_confirmed: false
    )
  end

  # Learn a rule from user's manual categorization (starts as active)
  def self.learn_from_user(transaction:, category:)
    description = transaction.entry.name
    return nil if description.blank?
    
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    
    existing = find_by(family: transaction.family, pattern: pattern.downcase)
    if existing
      if existing.category_id == category.id
        # User confirming existing rule
        existing.confirm!
      else
        # User correcting to different category
        existing.record_override!
        # Create new manual rule for correct category
        return create(
          family: transaction.family,
          category: category,
          pattern: pattern.downcase,
          match_type: determine_match_type(pattern),
          source: "manual",
          status: "active",
          confidence: MANUAL_CONFIDENCE,
          merchant_name: extract_merchant_name(description),
          user_confirmed: true
        )
      end
      return existing
    end
    
    create(
      family: transaction.family,
      category: category,
      pattern: pattern.downcase,
      match_type: determine_match_type(pattern),
      source: "manual",
      status: "active",  # Manual rules start active
      confidence: MANUAL_CONFIDENCE,
      merchant_name: extract_merchant_name(description),
      user_confirmed: true
    )
  end

  # ==========================================
  # EXPLANATION (for "Why was this categorized?")
  # ==========================================
  
  def explanation
    {
      type: "rule",
      rule_id: id,
      matched_pattern: pattern,
      match_type: match_type,
      category_name: category.name,
      source: source,
      source_label: source_label,
      confidence: confidence.round(2),
      stats: {
        times_matched: times_matched,
        times_overridden: times_overridden || 0,
        user_confirmed: user_confirmed?
      },
      created_at: created_at,
      human_readable: human_readable_explanation
    }
  end
  
  def source_label
    case source
    when "manual" then "You created this rule"
    when "system" then "Default system rule"
    when "ai" then user_confirmed? ? "AI (you confirmed)" : "AI learned"
    else "Auto-detected"
    end
  end
  
  def human_readable_explanation
    match_desc = case match_type
    when "exact" then "exactly matches"
    when "starts_with" then "starts with"
    when "ends_with" then "ends with"
    when "contains" then "contains"
    when "regex" then "matches pattern"
    end
    
    confidence_desc = if confidence >= 0.9
      "high confidence"
    elsif confidence >= 0.7
      "good confidence"
    elsif confidence >= 0.5
      "moderate confidence"
    else
      "low confidence"
    end
    
    "Transaction #{match_desc} \"#{pattern}\" → #{category.name} (#{source_label}, #{confidence_desc}, #{times_matched} matches)"
  end

  # ==========================================
  # HELPERS
  # ==========================================
  
  def self.determine_match_type(pattern)
    return "contains" if pattern.blank?
    
    # Very short patterns should be exact to avoid false positives
    return "exact" if pattern.length <= 4
    
    # Patterns that look like merchant names → starts_with
    if pattern.match?(/^[a-z]+$/i) && pattern.length >= 5
      return "starts_with"
    end
    
    "contains"
  end

  # Extract a meaningful pattern from a transaction description
  def self.extract_pattern(description)
    return nil if description.blank?
    
    normalized = normalize_description(description)
    return nil if normalized.blank?
    
    # Split into tokens and find the most meaningful one(s)
    tokens = normalized.split(/\s+/).reject { |t| t.length < 3 }
    
    # Remove very common noise words
    noise_words = %w[
      upi imps neft rtgs the and for from to via by at on in of
      debit credit transfer payment transaction ref no number
      mobile wallet bank account pvt ltd limited india
    ]
    meaningful_tokens = tokens.reject { |t| noise_words.include?(t) }
    
    # Take first 2-3 meaningful tokens
    pattern = meaningful_tokens.first(3).join(" ")
    
    # If still too generic, try full normalized but trimmed
    if pattern.length < 4 && normalized.length >= 4
      pattern = normalized.split(/\s+/).first(3).join(" ")
    end
    
    pattern.presence
  end

  def self.extract_merchant_name(description)
    return nil if description.blank?
    
    normalized = normalize_description(description)
    tokens = normalized.split(/\s+/).reject { |t| t.length < 3 }
    
    # First meaningful token is often the merchant
    tokens.first&.titleize
  end

  private

  def set_defaults
    self.status ||= (source == "manual" ? "active" : "candidate")
    self.confidence ||= (source == "manual" ? MANUAL_CONFIDENCE : INITIAL_AI_CONFIDENCE)
    self.times_matched ||= 0
    self.times_overridden ||= 0
    self.user_confirmed ||= (source == "manual")
  end
end
