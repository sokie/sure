class Offset < ApplicationRecord
  belongs_to :expense_transaction, class_name: "Transaction"
  belongs_to :offset_transaction, class_name: "Transaction"

  enum :status, { pending: "pending", confirmed: "confirmed" }

  validates :expense_transaction_id, uniqueness: { scope: :offset_transaction_id }
  validates :offset_transaction_id, uniqueness: true # An offset can only offset one expense

  validate :offset_has_same_category_or_uncategorized
  validate :offset_has_opposite_sign
  validate :offset_within_date_range
  validate :offset_has_same_family
  validate :expense_is_actually_expense
  validate :offset_is_actually_income

  def reject!
    Offset.transaction do
      RejectedOffset.find_or_create_by!(
        expense_transaction_id: expense_transaction_id,
        offset_transaction_id: offset_transaction_id
      )
      destroy!
    end
  end

  def confirm!
    update!(status: "confirmed")
  end

  def net_expense_amount
    expense_entry = expense_transaction.entry
    offset_entry = offset_transaction.entry

    # Expense is positive, offset is negative
    Money.new(expense_entry.amount + offset_entry.amount, expense_entry.currency)
  end

  def offset_amount
    offset_transaction.entry.amount_money.abs
  end

  def expense_amount
    expense_transaction.entry.amount_money.abs
  end

  def category
    expense_transaction.category
  end

  def date
    expense_transaction.entry.date
  end

  def sync_account_later
    expense_transaction&.entry&.sync_account_later
    offset_transaction&.entry&.sync_account_later
  end

  private

    def offset_has_same_category_or_uncategorized
      return unless expense_transaction && offset_transaction

      expense_cat_id = expense_transaction.category_id
      offset_cat_id = offset_transaction.category_id

      # Allow linking if: same category, offset is uncategorized, or expense is uncategorized
      unless expense_cat_id == offset_cat_id || offset_cat_id.nil? || expense_cat_id.nil?
        errors.add(:base, "Offset must have the same category as the expense or be uncategorized")
      end
    end

    def offset_has_opposite_sign
      return unless expense_transaction&.entry && offset_transaction&.entry

      expense_amount = expense_transaction.entry.amount
      offset_amount = offset_transaction.entry.amount

      unless expense_amount.positive? && offset_amount.negative?
        errors.add(:base, "Expense must be positive and offset must be negative")
      end
    end

    def offset_within_date_range
      return unless expense_transaction&.entry && offset_transaction&.entry

      date_diff = (expense_transaction.entry.date - offset_transaction.entry.date).abs
      max_days = status == "confirmed" ? 365 : 30

      errors.add(:base, "Must be within #{max_days} days") if date_diff > max_days
    end

    def offset_has_same_family
      return unless expense_transaction&.entry && offset_transaction&.entry

      expense_family = expense_transaction.entry.account.family
      offset_family = offset_transaction.entry.account.family

      errors.add(:base, "Must be from same family") unless expense_family == offset_family
    end

    def expense_is_actually_expense
      return unless expense_transaction&.entry
      errors.add(:expense_transaction, "must be an expense (positive amount)") unless expense_transaction.entry.amount.positive?
    end

    def offset_is_actually_income
      return unless offset_transaction&.entry
      errors.add(:offset_transaction, "must be an income/refund (negative amount)") unless offset_transaction.entry.amount.negative?
    end
end
