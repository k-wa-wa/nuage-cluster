# swfs-cluster の全ノード定義。swfs.nix と keepalived.nix で共有する
{
  swfs-cluster-1 = {
    ip = "10.20.1.61";
    # VIP を保持する優先度。ホスト名の若い順に高くする
    priority = 103;
  };
  swfs-cluster-2 = {
    ip = "10.20.1.62";
    priority = 102;
  };
  swfs-cluster-3 = {
    ip = "10.20.1.63";
    priority = 101;
  };
}
