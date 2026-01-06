module Transaction::Offsettable
  extend ActiveSupport::Concern

  included do
    # An expense can have multiple offsets (e.g., partial refunds)
    has_many :offsets_as_expense, class_name: "Offset", foreign_key: "expense_transaction_id", dependent: :destroy
    # An offset transaction can only offset one expense
    has_one :offset_as_offset, class_name: "Offset", foreign_key: "offset_transaction_id", dependent: :destroy

    # Track rejected offset matches to avoid re-suggesting them
    has_many :rejected_offsets_as_expense, class_name: "RejectedOffset", foreign_key: "expense_transaction_id", dependent: :destroy
    has_one :rejected_offset_as_offset, class_name: "RejectedOffset", foreign_key: "offset_transaction_id", dependent: :destroy
  end

  # Returns total offset amount for this expense transaction (only confirmed offsets)
  def total_offset_amount
    return Money.new(0, entry.currency) unless entry.amount.positive?

    # Sum the absolute value of all confirmed offset entry amounts
    total = offsets_as_expense.confirmed
              .joins("JOIN entries ON entries.entryable_id = offsets.offset_transaction_id AND entries.entryable_type = 'Transaction'")
              .sum("ABS(entries.amount)")

    Money.new(total, entry.currency)
  end

  # Net expense after deducting confirmed offsets
  def net_expense_amount
    return entry.amount_money unless entry.amount.positive?

    entry.amount_money - total_offset_amount
  end

  # Check if this transaction has any linked confirmed offsets
  def has_offsets?
    offsets_as_expense.confirmed.exists?
  end

  # Check if this transaction is linked as an offset to another expense
  def is_offset?
    offset_as_offset.present? && offset_as_offset.confirmed?
  end

  # Get offset match candidates for this expense transaction
  def offset_match_candidates(date_window: 30)
    return [] unless entry.amount.positive? # Only expenses can have offsets

    family_offset_matches_scope(date_window: date_window)
      .where("expense_candidates.entryable_id = ?", self.id)
      .map do |match|
        Offset.new(
          expense_transaction_id: match.expense_transaction_id,
          offset_transaction_id: match.offset_transaction_id
        )
      end
  end

  # Get expense match candidates for this refund/income transaction
  def expense_match_candidates(date_window: 30)
    return [] unless entry.amount.negative? # Only income/refunds can be offsets

    family_offset_matches_scope(date_window: date_window)
      .where("offset_candidates.entryable_id = ?", self.id)
      .map do |match|
        Offset.new(
          expense_transaction_id: match.expense_transaction_id,
          offset_transaction_id: match.offset_transaction_id
        )
      end
  end

  private

    def family_offset_matches_scope(date_window:)
      entry.account.family.offset_match_candidates(date_window: date_window)
    end
end
