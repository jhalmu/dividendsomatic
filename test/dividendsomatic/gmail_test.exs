defmodule Dividendsomatic.GmailTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Gmail

  describe "extract_date_from_subject/1" do
    test "extracts date from valid subject" do
      subject = "Activity Flex for 01/28/2026"
      result = Gmail.extract_date_from_subject(subject)

      assert result == ~D[2026-01-28]
    end

    test "extracts date with different months" do
      assert Gmail.extract_date_from_subject("Activity Flex for 12/25/2025") == ~D[2025-12-25]
      assert Gmail.extract_date_from_subject("Activity Flex for 06/15/2026") == ~D[2026-06-15]
    end

    test "returns today's date for invalid subject" do
      result = Gmail.extract_date_from_subject("Random email subject")

      assert result == Date.utc_today()
    end

    test "returns today's date for partially matching subject" do
      result = Gmail.extract_date_from_subject("Activity Flex")

      assert result == Date.utc_today()
    end

    test "returns today's date for invalid date values" do
      # Month 13 doesn't exist
      result = Gmail.extract_date_from_subject("Activity Flex for 13/01/2026")

      assert result == Date.utc_today()
    end
  end

  describe "search_activity_flex_emails/1" do
    test "returns empty list when OAuth not configured" do
      # Without Google OAuth credentials, should return empty list
      {:ok, emails} = Gmail.search_activity_flex_emails()

      assert emails == []
    end
  end

  describe "get_csv_from_email/1" do
    test "returns error when OAuth not configured" do
      result = Gmail.get_csv_from_email("test_message_id")

      assert result == {:error, :not_configured}
    end
  end
end
