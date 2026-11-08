require "test_helper"

class DirectUploadsTest < ActionDispatch::IntegrationTest
  test "nobody can put files on the server through Active Storage's direct uploads" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/rails/active_storage/direct_uploads", params: { blob: { filename: "x.html", byte_size: 10, checksum: "abc", content_type: "text/html" } }, as: :json
    end
    assert_response :not_found
  end
end
