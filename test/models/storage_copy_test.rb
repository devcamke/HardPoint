require "test_helper"

class StorageCopyTest < ActiveSupport::TestCase
  test "files move to the new service, blobs follow, and running it again is harmless" do
    Dir.mktmpdir do |root|
      target = ActiveStorage::Service::DiskService.new(root: root)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("proof of delivery"), filename: "note.jpg", content_type: "image/jpeg")
      untouched = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("elsewhere"), filename: "other.txt").tap { _1.update_columns(service_name: "local") }

      assert_equal 1, StorageCopy.new(from: "test", to: "object_storage", target: target).run
      assert_equal "object_storage", blob.reload.service_name
      assert_equal "proof of delivery", target.download(blob.key)
      assert_equal "local", untouched.reload.service_name

      assert_equal 0, StorageCopy.new(from: "test", to: "object_storage", target: target).run
    end
  end
end
