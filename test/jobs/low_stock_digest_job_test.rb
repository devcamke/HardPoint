require "test_helper"

class LowStockDigestJobTest < ActiveJob::TestCase
  test "emails each shop's managers what's running low" do
    perform_enqueued_jobs { LowStockDigestJob.perform_now }

    digest = ActionMailer::Base.deliveries.find { _1.subject.start_with?("Acme Hardware") }
    # Main: PVC pipe (3, reorder at 5). Yard: cement (10 of 20). The yard has never carried nails or pipes.
    assert_equal "Acme Hardware: 2 products to reorder", digest.subject
    assert_equal %w[ amina@acme.test sara@acme.test ].sort, digest.to.sort, "owners and stock clerks, not cashiers"
    assert_match "PVC pipe 2 inch 6m", digest.text_part.body.to_s
    assert_match "http://acme.localhost/reorder_list", digest.text_part.body.to_s

    assert ActionMailer::Base.deliveries.none? { _1.subject.start_with?("Bolt") }, "nothing low at Bolt"
  end
end
