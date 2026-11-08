# pg_dump writes "status IN ('queued', 'running')" differently from one Postgres major to the next
# (it's the array cast it spells out), so db/structure.sql flipped between machines on every
# migration. Two equalities come out the same everywhere. Same rows, same plan.
class MakeBackupsStatusIndexDumpTheSameEverywhere < ActiveRecord::Migration[8.1]
  def change
    remove_index :account_backups, :status, where: "status IN ('queued', 'running')"
    add_index :account_backups, :status, where: "status = 'queued' OR status = 'running'"
  end
end
