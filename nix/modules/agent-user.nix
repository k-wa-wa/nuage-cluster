# atelier のエージェントが SSH で入るためのユーザー。
#
# 権限は Mac の nixos ユーザーと同じ (wheel・パスワードなし sudo) にする。
# パスワードなし sudo は bootstrap.nix の security.sudo.wheelNeedsPassword = false で効く。
# journal も nixos と同じく wheel の ACL (systemd の tmpfiles) で全ユニット分を読めるので、systemd-journal には入れない。
#
# 権限が同じでも nixos の鍵を共有せず、ユーザーと鍵を分けるのは次のためである。
# - 鍵は atelier からしか使えない (from=)
# - atelier-agent.pub を消せば全ホストから失効できる
# - ログで人間の操作と区別できる
# - 転送を禁じられる (restrict)
# Mac の鍵は bootstrap.nix に直書きされ base イメージに焼かれた最後の手段なので、atelier には置かない。
#
# 鍵は Mac で scripts/setup-atelier-ssh-key.sh が作り、公開鍵を atelier-agent.pub に書き出す。
# ファイルが無ければ評価をエラーにする (既定値で黙って続けない)。
{ lib, ... }:

{
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    # 鍵は atelier の 2 本の足 (prvmain・LAN) からだけ使え、転送はすべて禁じる。
    openssh.authorizedKeys.keys = [
      ''restrict,pty,from="10.20.1.52,192.168.5.252" ${lib.trim (builtins.readFile ./atelier-agent.pub)}''
    ];
  };
}
