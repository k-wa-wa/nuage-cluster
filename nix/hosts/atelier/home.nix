# nixos ユーザーの環境 (シェル・エディタ・git の設定など) を nix-config から読み込む。
#
# 中身は Mac と共通で、nix-config の hosts/atelier/home.nix が決める。
# ここではシステム側の受け口 (ログインシェル・home-manager の動かし方) だけを定義する。
{
  pkgs,
  homeModule,
  unstablePkgs,
  ...
}:

{
  programs.zsh.enable = true;
  users.users.nixos.shell = pkgs.zsh;

  home-manager = {
    # nixpkgs はシステムと同じものを使い、パッケージは /etc/profiles/per-user に置く。
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit unstablePkgs; };
    # 手で置いたファイルと衝突したら、消さずに退避して進める。
    backupFileExtension = "hm-backup";
    users.nixos = homeModule;
  };
}
