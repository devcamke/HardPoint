# Moves every stored file (product photos, delivery proofs, exports) from one Active Storage service
# to another, for the switch from a server's disk to object storage when adding web servers. Files
# already at the target are skipped, so it can be run again after an interruption; each blob is
# pointed at the new service once its file is there.
class StorageCopy
  def initialize(from:, to:, source: ActiveStorage::Blob.services.fetch(from.to_sym), target: ActiveStorage::Blob.services.fetch(to.to_sym))
    @from, @to, @source, @target = from.to_s, to.to_s, source, target
  end

  def run
    moved = 0
    ActiveStorage::Blob.where(service_name: @from).find_each do |blob|
      unless @target.exist?(blob.key)
        @source.open(blob.key, checksum: blob.checksum) do |file|
          @target.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type)
        end
      end
      blob.update_columns(service_name: @to)
      moved += 1
    end
    moved
  end
end
