module Family::AutoOffsetMatchable
  # Find potential offset matches between expense and refund/income transactions
  # Criteria:
  # - Expense is positive, offset is negative
  # - Same category OR one is uncategorized
  # - Within date_window days of each other
  # - Same currency
  # - Offset amount <= expense amount (can't refund more than spent)
  # - Not already linked or rejected
  # - Standard transactions only (not transfers)
  def offset_match_candidates(date_window: 30)
    Entry.select([
      "expense_candidates.entryable_id as expense_transaction_id",
      "offset_candidates.entryable_id as offset_transaction_id",
      "ABS(expense_candidates.date - offset_candidates.date) as date_diff",
      "ABS(offset_candidates.amount) as offset_amount",
      "expense_candidates.amount as expense_amount"
    ]).from("entries expense_candidates")
      .joins("
        JOIN entries offset_candidates ON (
          expense_candidates.amount > 0 AND
          offset_candidates.amount < 0 AND
          expense_candidates.date BETWEEN offset_candidates.date - #{date_window.to_i} AND offset_candidates.date + #{date_window.to_i} AND
          expense_candidates.currency = offset_candidates.currency AND
          ABS(offset_candidates.amount) <= expense_candidates.amount
        )
      ")
      .joins("JOIN transactions expense_txns ON expense_txns.id = expense_candidates.entryable_id AND expense_candidates.entryable_type = 'Transaction'")
      .joins("JOIN transactions offset_txns ON offset_txns.id = offset_candidates.entryable_id AND offset_candidates.entryable_type = 'Transaction'")
      .joins("
        LEFT JOIN offsets existing_offsets ON (
          existing_offsets.expense_transaction_id = expense_candidates.entryable_id AND
          existing_offsets.offset_transaction_id = offset_candidates.entryable_id
        )
      ")
      .joins("
        LEFT JOIN offsets offset_already_used ON (
          offset_already_used.offset_transaction_id = offset_candidates.entryable_id
        )
      ")
      .joins("LEFT JOIN rejected_offsets ON (
        rejected_offsets.expense_transaction_id = expense_candidates.entryable_id AND
        rejected_offsets.offset_transaction_id = offset_candidates.entryable_id
      )")
      .joins("JOIN accounts expense_accounts ON expense_accounts.id = expense_candidates.account_id")
      .joins("JOIN accounts offset_accounts ON offset_accounts.id = offset_candidates.account_id")
      .where("expense_accounts.family_id = ? AND offset_accounts.family_id = ?", self.id, self.id)
      .where("expense_accounts.status IN ('draft', 'active')")
      .where("offset_accounts.status IN ('draft', 'active')")
      .where("expense_txns.kind = 'standard' AND offset_txns.kind = 'standard'") # Only standard transactions
      .where("expense_candidates.excluded = false AND offset_candidates.excluded = false")
      # Same category OR one is uncategorized
      .where("
        expense_txns.category_id = offset_txns.category_id OR
        expense_txns.category_id IS NULL OR
        offset_txns.category_id IS NULL
      ")
      .where(existing_offsets: { id: nil }) # Not already linked together
      .where(offset_already_used: { id: nil }) # Offset not already used for another expense
      .where(rejected_offsets: { id: nil }) # Not rejected
      .order("date_diff ASC, offset_amount DESC") # Closest date first, then largest offset
  end
end
