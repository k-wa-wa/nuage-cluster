function FindProxyForURL(url, host) {
  if (host == "192.168.5.100") {
      return "PROXY 192.168.1.70:3128";
  }

  return "DIRECT";
}
