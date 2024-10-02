# 
{ ... }:
{
  imports = [
    ./gitea.nix
    ./clickhouse.nix
    ./empty.nix
    ./empty-static.nix
    ./grafana.nix
    ./monitoring.nix
    ./nats.nix
    ./nettest.nix
    ./nginx.nix
    ./pmail.nix
    ./vault.nix
    ./unbound.nix
    ./unbound-sync.nix
    #./wgrouter.nix
  ];
}

