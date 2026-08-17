import Config

config :logger,
  level: :debug

config :exalia, :bootstrap_nodes, [
  {"router.bittorrent.com", 6881},
  {"dht.transmissionbt.com", 6881},
  {"router.utorrent.com", 6881}
]
