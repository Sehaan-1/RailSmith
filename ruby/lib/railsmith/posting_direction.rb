# frozen_string_literal: true
# typed: strict

module RailSmith
  # Direction of a double-entry posting. Serialization matches the
  # TypeScript engine.
  class PostingDirection < T::Enum
    enums do
      Debit = new('DEBIT')
      Credit = new('CREDIT')
    end
  end
end
