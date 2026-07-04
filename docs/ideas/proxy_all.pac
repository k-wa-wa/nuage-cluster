/* 全ての通信をプロキシする */
function FindProxyForURL(url, host) {
  if (host == "192.168.5.100") {
      return "PROXY 192.168.1.70:3128; PROXY 192.168.5.160:3128";
  }
  if (dnsDomainIs(host, ".nuage")) {
      return "PROXY 192.168.1.70:3128; PROXY 192.168.5.160:3128";
  }

  return "PROXY 192.168.1.70:3129; PROXY 192.168.5.160:3129";
}
