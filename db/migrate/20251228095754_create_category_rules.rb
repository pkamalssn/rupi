class CreateCategoryRules < ActiveRecord::Migration[7.2]
  def change
    create_table :category_rules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: true, type: :uuid  # For account-specific rules
      
      # Core matching
      t.string :pattern, null: false
      t.string :pattern_hash_exact                            # SHA256 hash for exact-match fast lookup ONLY
      t.string :match_type, default: "contains", null: false  # exact, starts_with, ends_with, contains, regex, regex_anchored
      t.string :scope, default: "narration", null: false      # global, narration, merchant, account_specific
      
      # Source and trust
      t.string :source, default: "auto", null: false          # manual, system, ai, auto
      t.string :status, default: "candidate", null: false     # candidate, active, inactive, quarantined
      t.boolean :probationary, default: true, null: false     # Still in probation period?
      
      # Confidence and scoring
      t.float :confidence, default: 0.65, null: false
      t.integer :priority, default: 0, null: false            # Calculated priority score
      t.boolean :user_confirmed, default: false, null: false
      
      # Stats for self-healing
      t.integer :times_matched, default: 0, null: false
      t.integer :times_overridden, default: 0, null: false
      t.datetime :last_overridden_at                          # For cooldown logic
      
      # Quarantine (for debugging failed rules)
      t.string :quarantine_reason
      t.datetime :quarantined_at
      
      # Metadata
      t.string :merchant_name

      t.timestamps
    end
    
    # ==========================================
    # INDEXES (Optimized for 10k+ users)
    # ==========================================
    
    # Unique pattern per family + scope
    add_index :category_rules, [:family_id, :pattern, :scope], unique: true, name: "idx_rules_unique_pattern"
    
    # FAST PATH: Hash lookup for exact matches only
    add_index :category_rules, [:family_id, :status, :pattern_hash_exact], name: "idx_rules_exact_hash_lookup"
    
    # Scope-based queries with status filter
    add_index :category_rules, [:family_id, :status, :scope], name: "idx_rules_scope_lookup"
    
    # Priority-ordered retrieval
    add_index :category_rules, [:family_id, :status, :priority], order: { priority: :desc }, name: "idx_rules_priority"
    
    # Category-based lookups (for rule management UI)
    add_index :category_rules, [:family_id, :category_id], name: "idx_rules_category"
    
    # Account-specific rule lookup
    add_index :category_rules, [:family_id, :account_id], name: "idx_rules_account"
    
    # Quarantine cleanup queries
    add_index :category_rules, [:family_id, :status, :quarantined_at], 
      where: "status = 'quarantined'", name: "idx_rules_quarantine_cleanup"
  end
end
