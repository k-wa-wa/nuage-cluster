
resource "truenas_dataset" "pool_1" {
  atime       = "OFF"
  compression = "LZ4"
  # full_path   = "/mnt/pool-1"
  # id          = "pool-1"
  # mount_path  = "/mnt/pool-1"
  quota       = "0"
  refquota    = "0"
}
