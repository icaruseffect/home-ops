server = "${upstream_server}"

[host."${harbor_url}"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
  override_path = true

[host."${upstream_server}"]
  capabilities = ["pull", "resolve"]
